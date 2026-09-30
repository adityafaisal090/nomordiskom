-- ============================================================================
-- MONA Migration 013: Final Notification Texts & isi_push Column
-- Menambahkan kolom isi_push dan memperbarui 4 RPC penomoran & approval
-- ============================================================================

-- 1. Tambah kolom isi_push ke tabel notifications
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS isi_push TEXT;

-- 2. Update issue_today_number dengan teks notifikasi final
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
  v_nama_operator text;
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

  SELECT coalesce(nama, username, 'Operator') INTO v_nama_operator FROM public.profiles WHERE id = auth.uid();
  IF v_nama_operator IS NULL THEN v_nama_operator := 'Operator'; END IF;

  -- Notifikasi ke semua admin (Bagian C)
  INSERT INTO public.notifications (user_id, tipe, judul, isi_push, isi, agenda_id)
  SELECT p.id, 'pengajuan_baru', 'Pengajuan Nomor Baru',
    v_nama_operator || ' — ' || p_kategori,
    v_nama_operator || ' mengajukan nomor agenda baru: ' ||
      p_kategori || ' — ' || v_row.nomor_lengkap || '. Perlu ditinjau.',
    v_row.id
  FROM public.profiles p WHERE lower(p.role) = 'admin';

  RETURN v_row;
END;
$$;

-- 3. Update issue_backdate_number dengan teks notifikasi final
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
  v_nama_operator text;
BEGIN
  SELECT frekuensi INTO v_frekuensi FROM public.buffer_settings WHERE kategori = p_kategori;
  IF v_frekuensi IS NULL THEN
    v_frekuensi := CASE WHEN p_kategori = 'surat_keluar' THEN 'harian' ELSE 'bulanan' END;
  END IF;

  -- Auto-generate buffer jika belum ada
  PERFORM public.generate_buffer_for_period(p_kategori, p_tanggal);

  IF v_frekuensi = 'harian' THEN
    SELECT id, nomor INTO v_buffer_id, v_nomor FROM public.agenda_buffers
      WHERE kategori = p_kategori AND periode = p_tanggal AND status = 'tersedia'
      ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;

    IF v_buffer_id IS NOT NULL THEN
      UPDATE public.agenda_buffers SET status = 'terpakai' WHERE id = v_buffer_id;
    END IF;
  ELSE
    SELECT id, nomor INTO v_buffer_id, v_nomor FROM public.agenda_buffers
      WHERE kategori = p_kategori
        AND date_trunc('month', periode) = date_trunc('month', p_tanggal)
        AND status = 'tersedia'
      ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;

    IF v_buffer_id IS NOT NULL THEN
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

  SELECT coalesce(nama, username, 'Operator') INTO v_nama_operator FROM public.profiles WHERE id = auth.uid();
  IF v_nama_operator IS NULL THEN v_nama_operator := 'Operator'; END IF;

  -- Notifikasi ke semua admin (Bagian C)
  INSERT INTO public.notifications (user_id, tipe, judul, isi_push, isi, agenda_id)
  SELECT p.id, 'pengajuan_baru', 'Pengajuan Nomor Baru',
    v_nama_operator || ' — ' || p_kategori,
    v_nama_operator || ' mengajukan nomor agenda baru: ' ||
      p_kategori || ' — ' || v_row.nomor_lengkap || '. Perlu ditinjau.',
    v_row.id
  FROM public.profiles p WHERE lower(p.role) = 'admin';

  RETURN v_row;
END;
$$;

-- 4. Update approve_agenda dengan teks notifikasi final
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

  -- Notifikasi ke Operator pembuat (Bagian C)
  INSERT INTO public.notifications (user_id, tipe, judul, isi_push, isi, agenda_id)
  VALUES (v_row.dibuat_oleh, 'acc', 'Nomor Agenda Disetujui',
    'Nomor ' || v_row.nomor_lengkap || ' telah disetujui.',
    'Nomor agenda Anda ' || v_row.nomor_lengkap || ' (' || v_row.kategori ||
      ') sudah disetujui admin dan siap diproses lebih lanjut.',
    v_row.id);

  RETURN v_row;
END;
$$;

-- 5. Update reject_agenda dengan teks notifikasi final
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

  -- Notifikasi ke Operator pembuat (Bagian C)
  INSERT INTO public.notifications (user_id, tipe, judul, isi_push, isi, agenda_id)
  VALUES (v_row.dibuat_oleh, 'tolak', 'Nomor Agenda Ditolak',
    'Nomor ' || v_row.nomor_lengkap || ' ditolak.',
    'Nomor agenda Anda ' || v_row.nomor_lengkap || ' (' || v_row.kategori || ') ditolak admin.' ||
      CASE WHEN p_catatan IS NOT NULL AND p_catatan <> ''
           THEN ' Catatan: ' || p_catatan ELSE '' END,
    v_row.id);

  RETURN v_row;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.issue_today_number(text, text, text, text, text) TO authenticated;
-- Note: keep backward compatibility parameter order
GRANT EXECUTE ON FUNCTION public.issue_backdate_number(date, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_agenda(int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_agenda(int, text) TO authenticated;
