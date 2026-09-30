-- ============================================================================
-- Migration 014: Stored Procedure for Updating Agenda Draft (Status Menunggu Only)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_agenda_draft(
  p_id BIGINT,
  p_kode_klasifikasi TEXT,
  p_tujuan_surat TEXT,
  p_perihal TEXT,
  p_pemohon TEXT
)
RETURNS public.agenda_numbers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.agenda_numbers;
  v_user_id UUID;
  v_user_role TEXT;
  v_user_name TEXT;
BEGIN
  -- 1. Identifikasi pemanggil
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Pengguna tidak terautentikasi.';
  END IF;

  SELECT role, nama INTO v_user_role, v_user_name
  FROM public.profiles
  WHERE id = v_user_id;

  -- 2. Ambil data agenda yang akan diedit dengan lock
  SELECT * INTO v_row
  FROM public.agenda_numbers
  WHERE id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_FOUND: Nomor agenda tidak ditemukan.';
  END IF;

  -- 3. Validasi status: hanya status 'menunggu' yang boleh diedit
  IF v_row.status_acc = 'disetujui' THEN
    RAISE EXCEPTION 'LOCKED: Nomor agenda sudah disetujui (ACC) dan terkunci total, tidak dapat diubah.';
  END IF;

  -- 4. Validasi input
  IF trim(COALESCE(p_kode_klasifikasi, '')) = '' THEN
    RAISE EXCEPTION 'INVALID_INPUT: Kode klasifikasi tidak boleh kosong.';
  END IF;

  IF trim(COALESCE(p_tujuan_surat, '')) = '' THEN
    RAISE EXCEPTION 'INVALID_INPUT: Tujuan surat tidak boleh kosong.';
  END IF;

  IF trim(COALESCE(p_perihal, '')) = '' THEN
    RAISE EXCEPTION 'INVALID_INPUT: Perihal tidak boleh kosong.';
  END IF;

  IF trim(COALESCE(p_pemohon, '')) = '' THEN
    RAISE EXCEPTION 'INVALID_INPUT: Pemohon tidak boleh kosong.';
  END IF;

  -- 5. Lakukan update data (HANYA field yang diizinkan, nomor dan tanggal tidak pernah berubah)
  UPDATE public.agenda_numbers
  SET
    kode_klasifikasi = trim(p_kode_klasifikasi),
    tujuan_surat = trim(p_tujuan_surat),
    perihal = trim(p_perihal),
    pemohon = trim(p_pemohon)
  WHERE id = p_id
  RETURNING * INTO v_row;

  -- 6. Catat audit trail ke activity_logs jika tabel tersedia
  BEGIN
    INSERT INTO public.activity_logs (user_id, action, details)
    VALUES (
      v_user_id,
      'UPDATE_DRAFT',
      jsonb_build_object(
        'agenda_id', p_id,
        'nomor_lengkap', v_row.nomor_lengkap,
        'kode_klasifikasi', v_row.kode_klasifikasi,
        'perihal', v_row.perihal,
        'updated_by', COALESCE(v_user_name, v_user_id::text)
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- Jangan gagalkan transaksi jika activity_logs tidak ada
    NULL;
  END;

  RETURN v_row;
END;
$$;

-- Berikan izin eksekusi ke authenticated user
GRANT EXECUTE ON FUNCTION public.update_agenda_draft(BIGINT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
