-- ============================================================================
-- SIAGENDA Sprint 2 — PATCH 005: Auto-Generate Daily Buffers & Fix Backdating
-- Fixes:
-- 1. Automatic +10 buffer reservation for past days when new day begins.
-- 2. Backdate number issuing for past days using reserved buffer numbers.
-- ============================================================================

-- ────────────────────────────────────────────
-- 1. ensure_daily_buffers() HELPER FUNCTION
-- ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ensure_daily_buffers()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := (now() AT TIME ZONE 'Asia/Jakarta')::DATE;
  v_today_year INT := EXTRACT(YEAR FROM v_today)::INT;
  v_start_date DATE;
  v_curr_date DATE;
  v_tahun INT;
  v_next INT;
BEGIN
  -- Determine earliest past date to check (earliest agenda number in current year, or v_today - 1)
  SELECT MIN(tanggal_agenda) INTO v_start_date
  FROM agenda_numbers
  WHERE tahun = v_today_year;

  IF v_start_date IS NULL THEN
    v_start_date := v_today - 1;
  END IF;

  IF v_start_date >= v_today THEN
    v_start_date := v_today - 1;
  END IF;

  -- Loop through all past dates up to (v_today - 1)
  v_curr_date := v_start_date;
  WHILE v_curr_date < v_today LOOP
    -- If this past date is in the current year and has not been buffered yet
    IF EXTRACT(YEAR FROM v_curr_date)::INT = v_today_year AND NOT EXISTS (
      SELECT 1 FROM buffer_generation_log WHERE tanggal = v_curr_date
    ) THEN
      v_tahun := EXTRACT(YEAR FROM v_curr_date)::INT;

      -- Lock year_counters for v_tahun
      INSERT INTO year_counters (tahun, next_number) VALUES (v_tahun, 1)
        ON CONFLICT (tahun) DO NOTHING;
      SELECT next_number INTO v_next FROM year_counters WHERE tahun = v_tahun FOR UPDATE;

      -- Insert 10 buffer numbers for v_curr_date
      INSERT INTO daily_buffers (tanggal, tahun, nomor, status)
      SELECT v_curr_date, v_tahun, v_next + i, 'tersedia'
      FROM generate_series(0, 9) AS i
      ON CONFLICT (tanggal, nomor) DO NOTHING;

      -- Advance counter by 10
      UPDATE year_counters SET next_number = v_next + 10 WHERE tahun = v_tahun;

      -- Mark date as buffered
      INSERT INTO buffer_generation_log (tanggal) VALUES (v_curr_date)
        ON CONFLICT (tanggal) DO NOTHING;
    END IF;

    v_curr_date := v_curr_date + 1;
  END LOOP;
END;
$$;


-- ────────────────────────────────────────────
-- 2. generate_daily_buffer(p_tanggal date)
-- ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_daily_buffer(p_tanggal date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tahun int := extract(year from p_tanggal);
  v_next int;
BEGIN
  -- Prevent duplicate generation for same date
  IF EXISTS (SELECT 1 FROM buffer_generation_log WHERE tanggal = p_tanggal) THEN
    RETURN;
  END IF;

  INSERT INTO year_counters (tahun, next_number) VALUES (v_tahun, 1)
    ON CONFLICT (tahun) DO NOTHING;
  SELECT next_number INTO v_next FROM year_counters WHERE tahun = v_tahun FOR UPDATE;

  INSERT INTO daily_buffers (tanggal, tahun, nomor, status)
  SELECT p_tanggal, v_tahun, v_next + i, 'tersedia'
  FROM generate_series(0, 9) AS i
  ON CONFLICT (tanggal, nomor) DO NOTHING;

  UPDATE year_counters SET next_number = v_next + 10 WHERE tahun = v_tahun;
  INSERT INTO buffer_generation_log (tanggal) VALUES (p_tanggal)
    ON CONFLICT (tanggal) DO NOTHING;
END;
$$;


-- ────────────────────────────────────────────
-- 3. issue_today_number(...)
-- ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.issue_today_number(
  p_kategori text, p_kode_klasifikasi text, p_kepada text,
  p_perihal text, p_pemohon text
) RETURNS agenda_numbers
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_tahun int := extract(year from v_today);
  v_nomor int;
  v_template text;
  v_row agenda_numbers;
BEGIN
  -- 1. Ensure all past days in current year have their 10 buffer numbers generated
  PERFORM ensure_daily_buffers();

  -- 2. Lock counter for current year
  INSERT INTO year_counters (tahun, next_number) VALUES (v_tahun, 1)
    ON CONFLICT (tahun) DO NOTHING;
  SELECT next_number INTO v_nomor FROM year_counters WHERE tahun = v_tahun FOR UPDATE;
  UPDATE year_counters SET next_number = next_number + 1 WHERE tahun = v_tahun;

  -- 3. Get active template
  SELECT template_tetap INTO v_template FROM template_settings WHERE is_active LIMIT 1;

  IF v_template IS NULL THEN
    RAISE EXCEPTION 'Template tetap belum dikonfigurasi. Hubungi admin.';
  END IF;

  -- 4. Insert agenda number record for today
  INSERT INTO agenda_numbers (tahun, nomor_agenda, nomor_lengkap, kategori,
    kode_klasifikasi, kepada, perihal, pemohon, tanggal_agenda, is_backdate,
    dibuat_oleh, status_acc)
  VALUES (v_tahun, v_nomor,
    p_kode_klasifikasi || ' / ' || v_nomor || ' / ' || v_template || '/' || v_tahun,
    p_kategori, p_kode_klasifikasi, p_kepada, p_perihal, p_pemohon,
    v_today, false, auth.uid(), 'menunggu')
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


-- ────────────────────────────────────────────
-- 4. issue_backdate_number(...)
-- ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.issue_backdate_number(
  p_tanggal date, p_kategori text, p_kode_klasifikasi text,
  p_kepada text, p_perihal text, p_pemohon text
) RETURNS agenda_numbers
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_buffer_id int;
  v_nomor int;
  v_tahun int := extract(year from p_tanggal);
  v_template text;
  v_row agenda_numbers;
BEGIN
  -- Validate: backdate date must be before today
  IF p_tanggal >= v_today THEN
    RAISE EXCEPTION 'Backdate hanya diperbolehkan untuk tanggal sebelum hari ini';
  END IF;

  -- 1. Ensure daily buffers for all past days up to yesterday are generated
  PERFORM ensure_daily_buffers();

  -- 2. If p_tanggal is still not buffered, generate on the fly
  IF NOT EXISTS (SELECT 1 FROM buffer_generation_log WHERE tanggal = p_tanggal) THEN
    PERFORM generate_daily_buffer(p_tanggal);
  END IF;

  -- 3. Grab available buffer for p_tanggal
  SELECT id, nomor INTO v_buffer_id, v_nomor FROM daily_buffers
    WHERE tanggal = p_tanggal AND status = 'tersedia'
    ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;

  IF v_buffer_id IS NULL THEN
    RAISE EXCEPTION 'BUFFER_HABIS: Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan koordinasi lebih lanjut dengan TU';
  END IF;

  -- 4. Mark buffer as used
  UPDATE daily_buffers SET status = 'terpakai' WHERE id = v_buffer_id;

  SELECT template_tetap INTO v_template FROM template_settings WHERE is_active LIMIT 1;

  IF v_template IS NULL THEN
    RAISE EXCEPTION 'Template tetap belum dikonfigurasi. Hubungi admin.';
  END IF;

  -- 5. Insert agenda number record with is_backdate = true
  INSERT INTO agenda_numbers (tahun, nomor_agenda, nomor_lengkap, kategori,
    kode_klasifikasi, kepada, perihal, pemohon, tanggal_agenda, is_backdate,
    dibuat_oleh, status_acc)
  VALUES (v_tahun, v_nomor,
    p_kode_klasifikasi || ' / ' || v_nomor || ' / ' || v_template || '/' || v_tahun,
    p_kategori, p_kode_klasifikasi, p_kepada, p_perihal, p_pemohon,
    p_tanggal, true, auth.uid(), 'menunggu')
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


-- ────────────────────────────────────────────
-- 5. GRANTS
-- ────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.ensure_daily_buffers() TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_daily_buffer(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_today_number(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_backdate_number(date, text, text, text, text, text) TO authenticated;
