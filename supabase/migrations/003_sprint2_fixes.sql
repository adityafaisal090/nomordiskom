-- ============================================================================
-- SIAGENDA Sprint 2 — PATCH: Fix RPC functions & RLS
-- Fixes: p_user_id → auth.uid(), buffer_generation_log, RLS lockdown
-- Run AFTER 002_sprint2_agenda.sql
-- ============================================================================

-- ────────────────────────────────────────────
-- 1. CREATE buffer_generation_log TABLE
-- ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.buffer_generation_log (
    id SERIAL PRIMARY KEY,
    tanggal DATE UNIQUE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.buffer_generation_log ENABLE ROW LEVEL SECURITY;
-- No RLS policy = no direct client access (only via SECURITY DEFINER RPC)


-- ────────────────────────────────────────────
-- 2. FIX RLS: Remove overly-permissive INSERT/UPDATE policies on agenda_numbers
-- ────────────────────────────────────────────
-- These policies allowed direct INSERT/UPDATE from any authenticated client,
-- bypassing the RPC functions. Only SELECT should be allowed directly.
DROP POLICY IF EXISTS "Authenticated users can insert agenda_numbers" ON public.agenda_numbers;
DROP POLICY IF EXISTS "Authenticated users can update agenda_numbers" ON public.agenda_numbers;


-- ────────────────────────────────────────────
-- 3. RECREATE RPC FUNCTIONS
-- Remove p_user_id parameter, use auth.uid() (per design.md §4)
-- Change RETURNS JSONB → RETURNS agenda_numbers (per design.md §4)
-- ────────────────────────────────────────────

-- ═══════════════════════════════════════════
-- 3.1 issue_today_number — design.md §4.1 EXACT
-- ═══════════════════════════════════════════
-- Drop old version (had extra p_user_id parameter)
DROP FUNCTION IF EXISTS public.issue_today_number(VARCHAR, VARCHAR, TEXT, TEXT, VARCHAR, UUID);
-- Drop in case the 5-param version already exists
DROP FUNCTION IF EXISTS public.issue_today_number(text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.issue_today_number(
  p_kategori text, p_kode_klasifikasi text, p_kepada text,
  p_perihal text, p_pemohon text
) RETURNS agenda_numbers
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tahun int := extract(year from (now() at time zone 'Asia/Jakarta'));
  v_nomor int;
  v_template text;
  v_row agenda_numbers;
BEGIN
  -- kunci baris counter tahun berjalan (buat kalau belum ada)
  INSERT INTO year_counters (tahun, next_number) VALUES (v_tahun, 1)
    ON CONFLICT (tahun) DO NOTHING;
  SELECT next_number INTO v_nomor FROM year_counters WHERE tahun = v_tahun FOR UPDATE;
  UPDATE year_counters SET next_number = next_number + 1 WHERE tahun = v_tahun;

  SELECT template_tetap INTO v_template FROM template_settings WHERE is_active LIMIT 1;

  IF v_template IS NULL THEN
    RAISE EXCEPTION 'Template tetap belum dikonfigurasi. Hubungi admin.';
  END IF;

  INSERT INTO agenda_numbers (tahun, nomor_agenda, nomor_lengkap, kategori,
    kode_klasifikasi, kepada, perihal, pemohon, tanggal_agenda, is_backdate,
    dibuat_oleh, status_acc)
  VALUES (v_tahun, v_nomor,
    p_kode_klasifikasi || ' / ' || v_nomor || ' / ' || v_template || '/' || v_tahun,
    p_kategori, p_kode_klasifikasi, p_kepada, p_perihal, p_pemohon,
    (now() at time zone 'Asia/Jakarta')::date, false, auth.uid(), 'menunggu')
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


-- ═══════════════════════════════════════════
-- 3.2 generate_daily_buffer — design.md §4.2 EXACT
-- Uses buffer_generation_log for idempotency (not COUNT(*))
-- ═══════════════════════════════════════════
-- Drop old version
DROP FUNCTION IF EXISTS public.generate_daily_buffer(DATE);

CREATE OR REPLACE FUNCTION public.generate_daily_buffer(p_tanggal date)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tahun int := extract(year from p_tanggal);
  v_next int;
BEGIN
  -- cegah generate dobel untuk tanggal yang sama
  IF EXISTS (SELECT 1 FROM buffer_generation_log WHERE tanggal = p_tanggal) THEN
    RETURN;
  END IF;

  INSERT INTO year_counters (tahun, next_number) VALUES (v_tahun, 1)
    ON CONFLICT (tahun) DO NOTHING;
  SELECT next_number INTO v_next FROM year_counters WHERE tahun = v_tahun FOR UPDATE;

  INSERT INTO daily_buffers (tanggal, tahun, nomor, status)
  SELECT p_tanggal, v_tahun, v_next + i, 'tersedia'
  FROM generate_series(0, 9) AS i;

  UPDATE year_counters SET next_number = v_next + 10 WHERE tahun = v_tahun;
  INSERT INTO buffer_generation_log (tanggal) VALUES (p_tanggal);
END;
$$;


-- ═══════════════════════════════════════════
-- 3.3 issue_backdate_number — design.md §4.3 EXACT
-- ═══════════════════════════════════════════
-- Drop old version (had extra p_user_id parameter)
DROP FUNCTION IF EXISTS public.issue_backdate_number(DATE, VARCHAR, VARCHAR, TEXT, TEXT, VARCHAR, UUID);
-- Drop in case the 6-param version already exists
DROP FUNCTION IF EXISTS public.issue_backdate_number(date, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.issue_backdate_number(
  p_tanggal date, p_kategori text, p_kode_klasifikasi text,
  p_kepada text, p_perihal text, p_pemohon text
) RETURNS agenda_numbers
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buffer_id int;
  v_nomor int;
  v_tahun int := extract(year from p_tanggal);
  v_template text;
  v_row agenda_numbers;
BEGIN
  SELECT id, nomor INTO v_buffer_id, v_nomor FROM daily_buffers
    WHERE tanggal = p_tanggal AND status = 'tersedia'
    ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;

  IF v_buffer_id IS NULL THEN
    RAISE EXCEPTION 'BUFFER_HABIS: Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan koordinasi lebih lanjut dengan TU';
  END IF;

  UPDATE daily_buffers SET status = 'terpakai' WHERE id = v_buffer_id;
  SELECT template_tetap INTO v_template FROM template_settings WHERE is_active LIMIT 1;

  IF v_template IS NULL THEN
    RAISE EXCEPTION 'Template tetap belum dikonfigurasi. Hubungi admin.';
  END IF;

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
-- 4. RE-GRANT EXECUTE for new function signatures
-- ────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.issue_today_number(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_daily_buffer(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_backdate_number(date, text, text, text, text, text) TO authenticated;
