-- ============================================================================
-- SIAGENDA Modul 4 Migration: Notifications, Buffer Auto-Gen, RPCs, & RLS
-- ============================================================================

-- 0. PROFILES TABLE (design.md 3.1) — harus ada sebelum tabel lain yang me-reference-nya
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username VARCHAR(50) UNIQUE NOT NULL,
    nama VARCHAR(100),
    role VARCHAR(20) NOT NULL DEFAULT 'operator' CHECK (role IN ('admin', 'operator')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    fcm_token TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Kalau tabel profiles sudah ada tapi belum ada kolom fcm_token
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- 2. NOTIFICATIONS TABLE
CREATE TABLE IF NOT EXISTS public.notifications (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    tipe VARCHAR(30) NOT NULL,
    judul TEXT NOT NULL,
    isi TEXT NOT NULL,
    agenda_id INT REFERENCES public.agenda_numbers(id) ON DELETE SET NULL,
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. AGENDA BUFFERS TABLE (per design.md 3.5)
CREATE TABLE IF NOT EXISTS public.agenda_buffers (
    id SERIAL PRIMARY KEY,
    kategori VARCHAR(30) NOT NULL,
    tahun INT NOT NULL,
    periode DATE NOT NULL,
    nomor INT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'tersedia' CHECK (status IN ('tersedia', 'terpakai'))
);

-- Ensure buffer_generation_log has required columns
ALTER TABLE public.buffer_generation_log ADD COLUMN IF NOT EXISTS periode DATE;
ALTER TABLE public.buffer_generation_log ADD COLUMN IF NOT EXISTS kategori VARCHAR(30);

-- Update buffer_generation_log PK if needed
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'buffer_generation_log' AND constraint_type = 'PRIMARY KEY'
  ) THEN
    ALTER TABLE public.buffer_generation_log ADD PRIMARY KEY (kategori, periode);
  END IF;
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

-- 4. RPC: generate_buffer_for_period (design.md 4.2)
CREATE OR REPLACE FUNCTION public.generate_buffer_for_period(p_kategori text, p_periode date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tahun int := extract(year from p_periode);
  v_next int;
  v_jumlah int;
BEGIN
  -- Cegah generate dobel untuk kategori + periode yang sama
  IF EXISTS (
    SELECT 1 FROM public.buffer_generation_log
    WHERE kategori = p_kategori AND (periode = p_periode OR tanggal = p_periode)
  ) THEN
    RETURN;
  END IF;

  SELECT jumlah_buffer INTO v_jumlah FROM public.buffer_settings WHERE kategori = p_kategori;
  IF v_jumlah IS NULL THEN v_jumlah := 5; END IF;

  INSERT INTO public.year_counters (tahun, kategori, next_number) VALUES (v_tahun, p_kategori, 1)
    ON CONFLICT (tahun, kategori) DO NOTHING;
  SELECT next_number INTO v_next FROM public.year_counters
    WHERE tahun = v_tahun AND kategori = p_kategori FOR UPDATE;

  -- Insert into agenda_buffers
  INSERT INTO public.agenda_buffers (kategori, tahun, periode, nomor, status)
  SELECT p_kategori, v_tahun, p_periode, v_next + i, 'tersedia'
  FROM generate_series(0, v_jumlah - 1) AS i;

  -- Also populate daily_buffers if table exists for backward compatibility
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='daily_buffers') THEN
    INSERT INTO public.daily_buffers (tanggal, bulan, tahun, kategori, frekuensi, nomor, status)
    SELECT p_periode, extract(month from p_periode)::int, v_tahun, p_kategori,
           coalesce((SELECT frekuensi FROM public.buffer_settings WHERE kategori = p_kategori LIMIT 1), 'harian'),
           v_next + i, 'tersedia'
    FROM generate_series(0, v_jumlah - 1) AS i;
  END IF;

  UPDATE public.year_counters SET next_number = v_next + v_jumlah
    WHERE tahun = v_tahun AND kategori = p_kategori;

  INSERT INTO public.buffer_generation_log (kategori, periode, tanggal, tahun, bulan)
  VALUES (p_kategori, p_periode, p_periode, v_tahun, extract(month from p_periode)::int)
  ON CONFLICT DO NOTHING;
END;
$$;

-- 5. SCHEDULE PG_CRON JOBS (design.md 4.2)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Hapus jadwal lama jika ada
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-buffer-harian') THEN
      PERFORM cron.unschedule('generate-buffer-harian');
    END IF;
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-buffer-bulanan') THEN
      PERFORM cron.unschedule('generate-buffer-bulanan');
    END IF;

    -- (a) Harian (surat_keluar) at 17:00 UTC = 00:00 WIB
    PERFORM cron.schedule(
      'generate-buffer-harian',
      '0 17 * * *',
      $cron$ SELECT public.generate_buffer_for_period('surat_keluar', (now() at time zone 'Asia/Jakarta')::date - 1); $cron$
    );

    -- (b) Bulanan (nota_dinas, surat_keputusan) on 1st of month at 17:00 UTC = 00:00 WIB
    PERFORM cron.schedule(
      'generate-buffer-bulanan',
      '0 17 1 * *',
      $cron$
      SELECT public.generate_buffer_for_period('nota_dinas',
        date_trunc('month', (now() at time zone 'Asia/Jakarta')::date - 1)::date);
      SELECT public.generate_buffer_for_period('surat_keputusan',
        date_trunc('month', (now() at time zone 'Asia/Jakarta')::date - 1)::date);
      $cron$
    );
  END IF;
END $$;

-- 6. RPC: update_buffer_setting (design.md 4.4)
DROP FUNCTION IF EXISTS public.update_buffer_setting(text, integer) CASCADE;
DROP FUNCTION IF EXISTS public.update_buffer_setting(text, int) CASCADE;
DROP FUNCTION IF EXISTS public.update_buffer_setting CASCADE;
DROP FUNCTION IF EXISTS update_buffer_setting CASCADE;

CREATE OR REPLACE FUNCTION public.update_buffer_setting(
  p_kategori text,
  p_jumlah int DEFAULT NULL,
  p_jumlah_buffer int DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_effective_jumlah int;
BEGIN
  v_effective_jumlah := coalesce(p_jumlah, p_jumlah_buffer);

  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role IS DISTINCT FROM 'admin' THEN
    SELECT raw_user_meta_data->>'role' INTO v_role FROM auth.users WHERE id = auth.uid();
  END IF;
  IF v_role IS DISTINCT FROM 'admin' AND lower(coalesce(v_role, '')) != 'admin' THEN
    RAISE EXCEPTION 'FORBIDDEN: hanya admin yang boleh mengubah pengaturan buffer';
  END IF;
  IF v_effective_jumlah IS NULL OR v_effective_jumlah < 1 THEN
    RAISE EXCEPTION 'INVALID_INPUT: jumlah buffer minimal 1';
  END IF;

  UPDATE public.buffer_settings SET jumlah_buffer = v_effective_jumlah WHERE kategori = p_kategori;
END;
$$;

-- 7. RPC: approve_agenda & reject_agenda (design.md 8.1)
CREATE OR REPLACE FUNCTION public.approve_agenda(p_id int)
RETURNS public.agenda_numbers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_row public.agenda_numbers;
BEGIN
  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role IS DISTINCT FROM 'admin' THEN
    SELECT raw_user_meta_data->>'role' INTO v_role FROM auth.users WHERE id = auth.uid();
  END IF;
  IF v_role IS DISTINCT FROM 'admin' AND lower(coalesce(v_role, '')) != 'admin' THEN
    RAISE EXCEPTION 'FORBIDDEN: hanya admin yang boleh meng-ACC';
  END IF;

  UPDATE public.agenda_numbers
  SET status_acc = 'disetujui', diacc_oleh = auth.uid(), diacc_pada = now()
  WHERE id = p_id AND status_acc = 'menunggu'
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND_OR_LOCKED: data tidak ditemukan atau sudah diproses sebelumnya';
  END IF;

  INSERT INTO public.notifications (user_id, tipe, judul, isi, agenda_id)
  VALUES (v_row.dibuat_oleh, 'acc', 'Nomor Agenda Disetujui',
    'Nomor agenda Anda ' || v_row.nomor_lengkap || ' telah disetujui.', v_row.id);

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_agenda(p_id int, p_catatan text DEFAULT NULL)
RETURNS public.agenda_numbers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
  v_row public.agenda_numbers;
BEGIN
  SELECT role INTO v_role FROM public.profiles WHERE id = auth.uid();
  IF v_role IS DISTINCT FROM 'admin' THEN
    SELECT raw_user_meta_data->>'role' INTO v_role FROM auth.users WHERE id = auth.uid();
  END IF;
  IF v_role IS DISTINCT FROM 'admin' AND lower(coalesce(v_role, '')) != 'admin' THEN
    RAISE EXCEPTION 'FORBIDDEN: hanya admin yang boleh menolak';
  END IF;

  UPDATE public.agenda_numbers
  SET status_acc = 'ditolak', catatan_admin = p_catatan,
      diacc_oleh = auth.uid(), diacc_pada = now()
  WHERE id = p_id AND status_acc = 'menunggu'
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND_OR_LOCKED: data tidak ditemukan atau sudah diproses sebelumnya';
  END IF;

  INSERT INTO public.notifications (user_id, tipe, judul, isi, agenda_id)
  VALUES (v_row.dibuat_oleh, 'tolak', 'Nomor Agenda Ditolak',
    'Nomor agenda Anda ' || v_row.nomor_lengkap || ' ditolak.' ||
      CASE WHEN p_catatan IS NOT NULL AND p_catatan <> '' THEN ' Catatan: ' || p_catatan ELSE '' END,
    v_row.id);

  RETURN v_row;
END;
$$;

-- 8. RPC: update_fcm_token (design.md 8.2)
CREATE OR REPLACE FUNCTION public.update_fcm_token(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, username, nama, role, fcm_token)
  SELECT 
    id,
    coalesce(raw_user_meta_data->>'username', split_part(email, '@', 1)),
    coalesce(raw_user_meta_data->>'nama', raw_user_meta_data->>'username', split_part(email, '@', 1)),
    coalesce(raw_user_meta_data->>'role', 'operator'),
    p_token
  FROM auth.users WHERE id = auth.uid()
  ON CONFLICT (id) DO UPDATE SET
    fcm_token = p_token;
END;
$$;

-- 9. UPDATE issue_today_number & issue_backdate_number WITH NOTIFICATIONS (design.md 4.1 & 4.3)
CREATE OR REPLACE FUNCTION public.issue_today_number(
  p_kategori text, p_kode_klasifikasi text, p_tujuan_surat text,
  p_perihal text, p_pemohon text
) RETURNS public.agenda_numbers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tahun int := extract(year from (now() at time zone 'Asia/Jakarta'));
  v_nomor int;
  v_template text;
  v_row public.agenda_numbers;
  v_pemohon_name text;
BEGIN
  INSERT INTO public.year_counters (tahun, kategori, next_number) VALUES (v_tahun, p_kategori, 1)
    ON CONFLICT (tahun, kategori) DO NOTHING;
  SELECT next_number INTO v_nomor FROM public.year_counters
    WHERE tahun = v_tahun AND kategori = p_kategori FOR UPDATE;
  UPDATE public.year_counters SET next_number = next_number + 1
    WHERE tahun = v_tahun AND kategori = p_kategori;

  SELECT template_tetap INTO v_template FROM public.template_settings WHERE is_active LIMIT 1;
  IF v_template IS NULL THEN v_template := '35.07.315'; END IF;

  INSERT INTO public.agenda_numbers (tahun, nomor_agenda, nomor_lengkap, kategori,
    kode_klasifikasi, tujuan_surat, perihal, pemohon, tanggal_agenda, is_backdate,
    dibuat_oleh, status_acc)
  VALUES (v_tahun, v_nomor,
    p_kode_klasifikasi || ' / ' || v_nomor || ' / ' || v_template || '/' || v_tahun,
    p_kategori, p_kode_klasifikasi, p_tujuan_surat, p_perihal, p_pemohon,
    (now() at time zone 'Asia/Jakarta')::date, false, auth.uid(), 'menunggu')
  RETURNING * INTO v_row;

  SELECT coalesce(nama, username, 'Operator') INTO v_pemohon_name FROM public.profiles WHERE id = auth.uid();

  -- Send notification to all admin profiles
  INSERT INTO public.notifications (user_id, tipe, judul, isi, agenda_id)
  SELECT p.id, 'pengajuan_baru', 'Pengajuan Nomor Baru',
    coalesce(v_pemohon_name, 'Operator') || ' mengajukan ' || p_kategori || ' — ' || v_row.nomor_lengkap,
    v_row.id
  FROM public.profiles p WHERE lower(p.role) = 'admin';

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue_backdate_number(
  p_tanggal date, p_kategori text, p_kode_klasifikasi text,
  p_tujuan_surat text, p_perihal text, p_pemohon text
) RETURNS public.agenda_numbers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_frekuensi text;
  v_buffer_id int;
  v_nomor int;
  v_tahun int := extract(year from p_tanggal);
  v_template text;
  v_row public.agenda_numbers;
  v_pemohon_name text;
BEGIN
  SELECT frekuensi INTO v_frekuensi FROM public.buffer_settings WHERE kategori = p_kategori;
  IF v_frekuensi IS NULL THEN
    v_frekuensi := CASE WHEN p_kategori = 'surat_keluar' THEN 'harian' ELSE 'bulanan' END;
  END IF;

  -- Attempt auto-generate if buffer missing
  PERFORM public.generate_buffer_for_period(p_kategori, p_tanggal);

  IF v_frekuensi = 'harian' THEN
    SELECT id, nomor INTO v_buffer_id, v_nomor FROM public.agenda_buffers
      WHERE kategori = p_kategori AND periode = p_tanggal AND status = 'tersedia'
      ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;

    IF v_buffer_id IS NULL AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='daily_buffers') THEN
      SELECT id, nomor INTO v_buffer_id, v_nomor FROM public.daily_buffers
        WHERE kategori = p_kategori AND tanggal = p_tanggal AND status = 'tersedia'
        ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;
      IF v_buffer_id IS NOT NULL THEN
        UPDATE public.daily_buffers SET status = 'terpakai' WHERE id = v_buffer_id;
      END IF;
    ELSEIF v_buffer_id IS NOT NULL THEN
      UPDATE public.agenda_buffers SET status = 'terpakai' WHERE id = v_buffer_id;
    END IF;
  ELSE
    SELECT id, nomor INTO v_buffer_id, v_nomor FROM public.agenda_buffers
      WHERE kategori = p_kategori
        AND date_trunc('month', periode) = date_trunc('month', p_tanggal)
        AND status = 'tersedia'
      ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;

    IF v_buffer_id IS NULL AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='daily_buffers') THEN
      SELECT id, nomor INTO v_buffer_id, v_nomor FROM public.daily_buffers
        WHERE kategori = p_kategori
          AND tahun = v_tahun AND bulan = extract(month from p_tanggal)::int
          AND status = 'tersedia'
        ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;
      IF v_buffer_id IS NOT NULL THEN
        UPDATE public.daily_buffers SET status = 'terpakai' WHERE id = v_buffer_id;
      END IF;
    ELSEIF v_buffer_id IS NOT NULL THEN
      UPDATE public.agenda_buffers SET status = 'terpakai' WHERE id = v_buffer_id;
    END IF;
  END IF;

  IF v_buffer_id IS NULL THEN
    RAISE EXCEPTION 'BUFFER_HABIS: Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan koordinasi lebih lanjut dengan TU';
  END IF;

  SELECT template_tetap INTO v_template FROM public.template_settings WHERE is_active LIMIT 1;
  IF v_template IS NULL THEN v_template := '35.07.315'; END IF;

  INSERT INTO public.agenda_numbers (tahun, nomor_agenda, nomor_lengkap, kategori,
    kode_klasifikasi, tujuan_surat, perihal, pemohon, tanggal_agenda, is_backdate,
    dibuat_oleh, status_acc)
  VALUES (v_tahun, v_nomor,
    p_kode_klasifikasi || ' / ' || v_nomor || ' / ' || v_template || '/' || v_tahun,
    p_kategori, p_kode_klasifikasi, p_tujuan_surat, p_perihal, p_pemohon,
    p_tanggal, true, auth.uid(), 'menunggu')
  RETURNING * INTO v_row;

  SELECT coalesce(nama, username, 'Operator') INTO v_pemohon_name FROM public.profiles WHERE id = auth.uid();

  -- Send notification to all admin profiles
  INSERT INTO public.notifications (user_id, tipe, judul, isi, agenda_id)
  SELECT p.id, 'pengajuan_baru', 'Pengajuan Nomor Baru',
    coalesce(v_pemohon_name, 'Operator') || ' mengajukan ' || p_kategori || ' — ' || v_row.nomor_lengkap,
    v_row.id
  FROM public.profiles p WHERE lower(p.role) = 'admin';

  RETURN v_row;
END;
$$;

-- 10. RLS POLICIES FOR NOTIFICATIONS (design.md 8.6)
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'notifications' AND policyname = 'Users can select own notifications'
  ) THEN
    CREATE POLICY "Users can select own notifications"
      ON public.notifications FOR SELECT
      TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'notifications' AND policyname = 'Users can update own notifications'
  ) THEN
    CREATE POLICY "Users can update own notifications"
      ON public.notifications FOR UPDATE
      TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- Enable RLS on all other system tables for audit compliance (design.md section 7 & 10)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agenda_numbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.year_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agenda_buffers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.buffer_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.template_settings ENABLE ROW LEVEL SECURITY;

-- Grant permissions to authenticated role
GRANT EXECUTE ON FUNCTION public.generate_buffer_for_period(text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_buffer_setting(text, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_agenda(int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_agenda(int, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_fcm_token(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_today_number(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_backdate_number(date, text, text, text, text, text) TO authenticated;
