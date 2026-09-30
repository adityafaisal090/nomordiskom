-- ============================================================================
-- MONA Migration 015: Auto-Generate Buffer on Issue Today Number
-- Memastikan buffer cadangan tanggal kemarin/bulan lalu otomatis terbentuk
-- saat pergantian hari/bulan tanpa tergantung pg_cron.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.issue_today_number(
  p_kategori text, p_kode_klasifikasi text, p_tujuan_surat text,
  p_perihal text, p_pemohon text
) RETURNS public.agenda_numbers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today date := (now() at time zone 'Asia/Jakarta')::date;
  v_yesterday date := v_today - 1;
  v_prev_month date := (date_trunc('month', v_today) - interval '1 day')::date;
  v_tahun int := extract(year from v_today);
  v_nomor int;
  v_template text;
  v_row public.agenda_numbers;
  v_nama_operator text;
  v_frekuensi text;
BEGIN
  -- 1. Cek frekuensi buffer untuk kategori ini
  SELECT frekuensi INTO v_frekuensi FROM public.buffer_settings WHERE kategori = p_kategori;
  IF v_frekuensi IS NULL THEN
    v_frekuensi := CASE WHEN p_kategori = 'surat_keluar' THEN 'harian' ELSE 'bulanan' END;
  END IF;

  -- 2. Auto-generate buffer periode sebelumnya jika belum pernah dibuat
  -- (Membuat cadangan 5 nomor untuk kemarin/bulan lalu jika hari/bulan baru dimulai)
  IF v_frekuensi = 'harian' THEN
    PERFORM public.generate_buffer_for_period(p_kategori, v_yesterday);
  ELSE
    PERFORM public.generate_buffer_for_period(p_kategori, v_prev_month);
  END IF;

  -- 3. Ambil nomor counter tahunan terbaru (yang sudah melewati nomor buffer)
  INSERT INTO public.year_counters (tahun, kategori, next_number) VALUES (v_tahun, p_kategori, 1)
    ON CONFLICT (tahun, kategori) DO NOTHING;
  SELECT next_number INTO v_nomor FROM public.year_counters
    WHERE tahun = v_tahun AND kategori = p_kategori FOR UPDATE;
  UPDATE public.year_counters SET next_number = next_number + 1
    WHERE tahun = v_tahun AND kategori = p_kategori;

  -- 4. Ambil format template tetap
  SELECT template_tetap INTO v_template FROM public.template_settings WHERE is_active LIMIT 1;
  IF v_template IS NULL THEN v_template := '35.07.315'; END IF;

  -- 5. Insert data nomor agenda baru
  INSERT INTO public.agenda_numbers (tahun, nomor_agenda, nomor_lengkap, kategori,
    kode_klasifikasi, tujuan_surat, perihal, pemohon, tanggal_agenda, is_backdate,
    dibuat_oleh, status_acc)
  VALUES (v_tahun, v_nomor,
    p_kode_klasifikasi || ' / ' || v_nomor || ' / ' || v_template || '/' || v_tahun,
    p_kategori, p_kode_klasifikasi, p_tujuan_surat, p_perihal, p_pemohon,
    v_today, false, auth.uid(), 'menunggu')
  RETURNING * INTO v_row;

  -- 6. Kirim notifikasi push & in-app ke semua Admin
  SELECT coalesce(nama, username, 'Operator') INTO v_nama_operator FROM public.profiles WHERE id = auth.uid();
  IF v_nama_operator IS NULL THEN v_nama_operator := 'Operator'; END IF;

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
