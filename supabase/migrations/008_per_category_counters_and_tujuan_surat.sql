-- ============================================================================
-- SIAGENDA Sprint 3 — Migration 008: Per-Category Counters, Tujuan Surat, & Buffer Settings
-- ============================================================================

-- ────────────────────────────────────────────
-- 1. TABLE STRUCTURAL UPDATES
-- ────────────────────────────────────────────

-- 1.1 Update year_counters table to per-category (tahun, kategori) composite PK
DO $$
BEGIN
  -- Drop existing PK constraint if year_counters exists with single column PK
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'year_counters' AND constraint_type = 'PRIMARY KEY'
  ) THEN
    ALTER TABLE public.year_counters DROP CONSTRAINT year_counters_pkey;
  END IF;
END $$;

ALTER TABLE public.year_counters ADD COLUMN IF NOT EXISTS kategori VARCHAR(30) NOT NULL DEFAULT 'surat_keluar';

-- Clean up any NULLs before creating composite PK
UPDATE public.year_counters SET kategori = 'surat_keluar' WHERE kategori IS NULL;

-- Set composite primary key
ALTER TABLE public.year_counters ADD CONSTRAINT year_counters_pkey PRIMARY KEY (tahun, kategori);

-- Seed category counters for current and next year if missing
INSERT INTO public.year_counters (tahun, kategori, next_number) VALUES
  (EXTRACT(YEAR FROM now())::INTEGER, 'surat_keluar', 1),
  (EXTRACT(YEAR FROM now())::INTEGER, 'nota_dinas', 1),
  (EXTRACT(YEAR FROM now())::INTEGER, 'surat_keputusan', 1)
ON CONFLICT (tahun, kategori) DO NOTHING;


-- 1.2 Rename `kepada` -> `tujuan_surat` in agenda_numbers
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'agenda_numbers' AND column_name = 'kepada'
  ) THEN
    ALTER TABLE public.agenda_numbers RENAME COLUMN kepada TO tujuan_surat;
  END IF;
END $$;


-- 1.3 Create buffer_settings table
CREATE TABLE IF NOT EXISTS public.buffer_settings (
    kategori VARCHAR(30) PRIMARY KEY CHECK (kategori IN ('surat_keputusan', 'nota_dinas', 'surat_keluar')),
    jumlah_buffer INTEGER NOT NULL DEFAULT 5 CHECK (jumlah_buffer > 0),
    frekuensi VARCHAR(20) NOT NULL CHECK (frekuensi IN ('harian', 'bulanan')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed buffer_settings defaults
INSERT INTO public.buffer_settings (kategori, jumlah_buffer, frekuensi) VALUES
  ('surat_keluar', 5, 'harian'),
  ('nota_dinas', 5, 'bulanan'),
  ('surat_keputusan', 5, 'bulanan')
ON CONFLICT (kategori) DO NOTHING;


-- 1.4 Update daily_buffers table to support category, month, & frequency
ALTER TABLE public.daily_buffers ADD COLUMN IF NOT EXISTS kategori VARCHAR(30) NOT NULL DEFAULT 'surat_keluar';
ALTER TABLE public.daily_buffers ADD COLUMN IF NOT EXISTS bulan INTEGER;
ALTER TABLE public.daily_buffers ADD COLUMN IF NOT EXISTS frekuensi VARCHAR(20) NOT NULL DEFAULT 'harian';


-- 1.5 Update buffer_generation_log table
ALTER TABLE public.buffer_generation_log ADD COLUMN IF NOT EXISTS kategori VARCHAR(30) NOT NULL DEFAULT 'surat_keluar';
ALTER TABLE public.buffer_generation_log ADD COLUMN IF NOT EXISTS bulan INTEGER;
ALTER TABLE public.buffer_generation_log ADD COLUMN IF NOT EXISTS tahun INTEGER;


-- ────────────────────────────────────────────
-- 2. HELPER & RPC FUNCTIONS
-- ────────────────────────────────────────────

-- 2.1 generate_category_buffer(p_kategori text, p_tanggal date)
CREATE OR REPLACE FUNCTION public.generate_category_buffer(p_kategori text, p_tanggal date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tahun int := EXTRACT(YEAR FROM p_tanggal)::int;
  v_bulan int := EXTRACT(MONTH FROM p_tanggal)::int;
  v_frekuensi text;
  v_jumlah int;
  v_next int;
  v_periode_date date;
BEGIN
  -- Validate category
  IF p_kategori NOT IN ('surat_keputusan', 'nota_dinas', 'surat_keluar') THEN
    RAISE EXCEPTION 'Kategori tidak valid: %', p_kategori;
  END IF;

  -- Fetch settings
  SELECT frekuensi, jumlah_buffer INTO v_frekuensi, v_jumlah
  FROM public.buffer_settings WHERE kategori = p_kategori;

  IF v_frekuensi IS NULL THEN
    IF p_kategori = 'surat_keluar' THEN
      v_frekuensi := 'harian';
    ELSE
      v_frekuensi := 'bulanan';
    END IF;
    v_jumlah := 5;
  END IF;

  -- Determine period key
  IF v_frekuensi = 'harian' THEN
    v_periode_date := p_tanggal;

    IF EXISTS (
      SELECT 1 FROM public.buffer_generation_log
      WHERE kategori = p_kategori AND tanggal = v_periode_date
    ) THEN
      RETURN;
    END IF;
  ELSE
    v_periode_date := date_trunc('month', p_tanggal)::date;

    IF EXISTS (
      SELECT 1 FROM public.buffer_generation_log
      WHERE kategori = p_kategori AND tahun = v_tahun AND bulan = v_bulan
    ) THEN
      RETURN;
    END IF;
  END IF;

  -- Lock year_counters for (v_tahun, p_kategori)
  INSERT INTO public.year_counters (tahun, kategori, next_number)
  VALUES (v_tahun, p_kategori, 1)
  ON CONFLICT (tahun, kategori) DO NOTHING;

  SELECT next_number INTO v_next
  FROM public.year_counters
  WHERE tahun = v_tahun AND kategori = p_kategori
  FOR UPDATE;

  -- Insert reserved buffer numbers
  INSERT INTO public.daily_buffers (tanggal, bulan, tahun, kategori, frekuensi, nomor, status)
  SELECT v_periode_date, v_bulan, v_tahun, p_kategori, v_frekuensi, v_next + i, 'tersedia'
  FROM generate_series(0, v_jumlah - 1) AS i;

  -- Advance category counter
  UPDATE public.year_counters
  SET next_number = v_next + v_jumlah
  WHERE tahun = v_tahun AND kategori = p_kategori;

  -- Log buffer generation
  INSERT INTO public.buffer_generation_log (kategori, tanggal, bulan, tahun)
  VALUES (p_kategori, v_periode_date, v_bulan, v_tahun);
END;
$$;


-- 2.2 generate_daily_buffer(p_tanggal date) — wrapper for backward compatibility
CREATE OR REPLACE FUNCTION public.generate_daily_buffer(p_tanggal date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.generate_category_buffer('surat_keluar', p_tanggal);
  PERFORM public.generate_category_buffer('nota_dinas', p_tanggal);
  PERFORM public.generate_category_buffer('surat_keputusan', p_tanggal);
END;
$$;


-- 2.3 issue_today_number(...)
DROP FUNCTION IF EXISTS public.issue_today_number(text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.issue_today_number(
  p_kategori text,
  p_kode_klasifikasi text,
  p_tujuan_surat text,
  p_perihal text,
  p_pemohon text
) RETURNS agenda_numbers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_tahun int := EXTRACT(YEAR FROM v_today)::int;
  v_nomor int;
  v_template text;
  v_row agenda_numbers;
BEGIN
  -- Lock counter for current year & category
  INSERT INTO public.year_counters (tahun, kategori, next_number)
  VALUES (v_tahun, p_kategori, 1)
  ON CONFLICT (tahun, kategori) DO NOTHING;

  SELECT next_number INTO v_nomor
  FROM public.year_counters
  WHERE tahun = v_tahun AND kategori = p_kategori
  FOR UPDATE;

  UPDATE public.year_counters
  SET next_number = next_number + 1
  WHERE tahun = v_tahun AND kategori = p_kategori;

  -- Fetch active template
  SELECT template_tetap INTO v_template FROM public.template_settings WHERE is_active LIMIT 1;
  IF v_template IS NULL THEN
    RAISE EXCEPTION 'Template tetap belum dikonfigurasi. Hubungi admin.';
  END IF;

  -- Insert agenda record
  INSERT INTO public.agenda_numbers (
    tahun, nomor_agenda, nomor_lengkap, kategori,
    kode_klasifikasi, tujuan_surat, perihal, pemohon, tanggal_agenda, is_backdate,
    dibuat_oleh, status_acc
  ) VALUES (
    v_tahun, v_nomor,
    p_kode_klasifikasi || ' / ' || v_nomor || ' / ' || v_template || '/' || v_tahun,
    p_kategori, p_kode_klasifikasi, p_tujuan_surat, p_perihal, p_pemohon,
    v_today, false, auth.uid(), 'menunggu'
  ) RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


-- 2.4 issue_backdate_number(...)
DROP FUNCTION IF EXISTS public.issue_backdate_number(date, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.issue_backdate_number(
  p_tanggal date,
  p_kategori text,
  p_kode_klasifikasi text,
  p_tujuan_surat text,
  p_perihal text,
  p_pemohon text
) RETURNS agenda_numbers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_buffer_id int;
  v_nomor int;
  v_tahun int := EXTRACT(YEAR FROM p_tanggal)::int;
  v_bulan int := EXTRACT(MONTH FROM p_tanggal)::int;
  v_frekuensi text;
  v_template text;
  v_row agenda_numbers;
BEGIN
  IF p_tanggal >= v_today THEN
    RAISE EXCEPTION 'Backdate hanya diperbolehkan untuk tanggal sebelum hari ini';
  END IF;

  SELECT frekuensi INTO v_frekuensi FROM public.buffer_settings WHERE kategori = p_kategori;
  IF v_frekuensi IS NULL THEN
    v_frekuensi := CASE WHEN p_kategori = 'surat_keluar' THEN 'harian' ELSE 'bulanan' END;
  END IF;

  -- Auto-generate buffer for period if missing
  PERFORM public.generate_category_buffer(p_kategori, p_tanggal);

  -- Allocate next available buffer in pool
  IF v_frekuensi = 'harian' THEN
    SELECT id, nomor INTO v_buffer_id, v_nomor
    FROM public.daily_buffers
    WHERE kategori = p_kategori AND tanggal = p_tanggal AND status = 'tersedia'
    ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;
  ELSE
    SELECT id, nomor INTO v_buffer_id, v_nomor
    FROM public.daily_buffers
    WHERE kategori = p_kategori AND tahun = v_tahun AND bulan = v_bulan AND status = 'tersedia'
    ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;
  END IF;

  IF v_buffer_id IS NULL THEN
    RAISE EXCEPTION 'BUFFER_HABIS: Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan koordinasi lebih lanjut dengan TU';
  END IF;

  UPDATE public.daily_buffers SET status = 'terpakai' WHERE id = v_buffer_id;

  SELECT template_tetap INTO v_template FROM public.template_settings WHERE is_active LIMIT 1;
  IF v_template IS NULL THEN
    RAISE EXCEPTION 'Template tetap belum dikonfigurasi. Hubungi admin.';
  END IF;

  INSERT INTO public.agenda_numbers (
    tahun, nomor_agenda, nomor_lengkap, kategori,
    kode_klasifikasi, tujuan_surat, perihal, pemohon, tanggal_agenda, is_backdate,
    dibuat_oleh, status_acc
  ) VALUES (
    v_tahun, v_nomor,
    p_kode_klasifikasi || ' / ' || v_nomor || ' / ' || v_template || '/' || v_tahun,
    p_kategori, p_kode_klasifikasi, p_tujuan_surat, p_perihal, p_pemohon,
    p_tanggal, true, auth.uid(), 'menunggu'
  ) RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


-- 2.5 update_buffer_setting(p_kategori text, p_jumlah_buffer int)
CREATE OR REPLACE FUNCTION public.update_buffer_setting(
  p_kategori text,
  p_jumlah_buffer int
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  -- Fetch user role from auth.users user metadata or JWT
  SELECT raw_user_meta_data->>'role' INTO v_role
  FROM auth.users
  WHERE id = auth.uid();

  IF v_role IS NULL THEN
    v_role := auth.jwt() -> 'user_metadata' ->> 'role';
  END IF;

  IF v_role IS NULL OR lower(v_role) != 'admin' THEN
    RAISE EXCEPTION 'FORBIDDEN: Hanya Admin yang dapat mengubah jumlah buffer';
  END IF;

  IF p_kategori NOT IN ('surat_keputusan', 'nota_dinas', 'surat_keluar') THEN
    RAISE EXCEPTION 'Kategori tidak valid: %', p_kategori;
  END IF;

  IF p_jumlah_buffer <= 0 THEN
    RAISE EXCEPTION 'Jumlah buffer harus lebih besar dari 0';
  END IF;

  UPDATE public.buffer_settings
  SET jumlah_buffer = p_jumlah_buffer,
      updated_at = now()
  WHERE kategori = p_kategori;
END;
$$;

-- ────────────────────────────────────────────
-- 3. PERMISSIONS & RLS
-- ────────────────────────────────────────────
ALTER TABLE public.buffer_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read buffer_settings"
  ON public.buffer_settings FOR SELECT
  TO authenticated USING (true);

GRANT EXECUTE ON FUNCTION public.issue_today_number(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_backdate_number(date, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_category_buffer(text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_daily_buffer(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_buffer_setting(text, int) TO authenticated;
