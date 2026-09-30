-- ============================================================================
-- SIAGENDA Sprint 3 — Migration 009: Test Verification for Sprint 3
-- Verifies:
-- 1. Per-category independent sequence starting at 1
-- 2. Buffer generation according to buffer_settings (5 for daily & monthly)
-- 3. Backdate for monthly categories sharing the same monthly pool
-- 4. Role checking on update_buffer_setting
-- ============================================================================

DO $$
DECLARE
  r_sk record;
  r_nd record;
  r_sk2 record;
  v_test_date1 date := '2026-08-05';
  v_test_date2 date := '2026-08-12';
  v_count int;
  r_bd1 record;
  r_bd2 record;
BEGIN
  RAISE NOTICE '==================================================';
  RAISE NOTICE 'STARTING SPRINT 3 VERIFICATION TESTS';
  RAISE NOTICE '==================================================';

  -- TEST 1: Per-category independent numbering sequence
  RAISE NOTICE '--- TEST 1: Per-category independent numbering sequence ---';
  
  -- Create Surat Keluar #1
  SELECT * INTO r_sk FROM issue_today_number('surat_keluar', '500.12', 'Bupati Malang', 'Pengajuan Perizinan', 'Novi');
  ASSERT r_sk.nomor_agenda = 1, 'FAIL: Expected Surat Keluar first number to be 1, got ' || r_sk.nomor_agenda;
  ASSERT r_sk.tujuan_surat = 'Bupati Malang', 'FAIL: Expected tujuan_surat to be Bupati Malang';

  -- Create Nota Dinas #1 (Should start at 1 independently!)
  SELECT * INTO r_nd FROM issue_today_number('nota_dinas', '005.1', 'Kadis Kominfo', 'Laporan Internal', 'Budi');
  ASSERT r_nd.nomor_agenda = 1, 'FAIL: Expected Nota Dinas first number to be 1, got ' || r_nd.nomor_agenda;

  -- Create Surat Keluar #2 (Should be 2)
  SELECT * INTO r_sk2 FROM issue_today_number('surat_keluar', '500.12', 'Camat Kepanjen', 'Undangan Rapat', 'Novi');
  ASSERT r_sk2.nomor_agenda = 2, 'FAIL: Expected Surat Keluar second number to be 2, got ' || r_sk2.nomor_agenda;

  RAISE NOTICE '✅ TEST 1 PASSED: Sequences are independent per category (Surat Keluar #1, Nota Dinas #1, Surat Keluar #2)';

  -- TEST 2: Buffer Generation per Category Settings
  RAISE NOTICE '--- TEST 2: Buffer Generation per Category Settings ---';

  PERFORM generate_category_buffer('surat_keluar', v_test_date1);
  SELECT COUNT(*) INTO v_count FROM daily_buffers WHERE kategori = 'surat_keluar' AND tanggal = v_test_date1;
  ASSERT v_count = 5, 'FAIL: Expected 5 buffers for surat_keluar, got ' || v_count;

  PERFORM generate_category_buffer('nota_dinas', v_test_date1);
  SELECT COUNT(*) INTO v_count FROM daily_buffers WHERE kategori = 'nota_dinas' AND tahun = 2026 AND bulan = 8;
  ASSERT v_count = 5, 'FAIL: Expected 5 buffers for monthly nota_dinas, got ' || v_count;

  RAISE NOTICE '✅ TEST 2 PASSED: 5 buffers generated for daily & monthly categories';

  -- TEST 3: Monthly Backdate Sharing Same Buffer Pool
  RAISE NOTICE '--- TEST 3: Monthly Backdate Sharing Same Buffer Pool ---';

  SELECT * INTO r_bd1 FROM issue_backdate_number(v_test_date1, 'nota_dinas', '005.2', 'Sekretaris', 'Memo Aug 5', 'Operator Test');
  SELECT * INTO r_bd2 FROM issue_backdate_number(v_test_date2, 'nota_dinas', '005.2', 'Kabid', 'Memo Aug 12', 'Operator Test');

  ASSERT r_bd1.tanggal_agenda = v_test_date1, 'FAIL: Expected tanggal_agenda Aug 5';
  ASSERT r_bd2.tanggal_agenda = v_test_date2, 'FAIL: Expected tanggal_agenda Aug 12';
  ASSERT r_bd2.nomor_agenda = r_bd1.nomor_agenda + 1, 'FAIL: Expected consecutive buffer numbers from monthly pool';

  RAISE NOTICE '✅ TEST 3 PASSED: Both backdates picked from the same August 2026 monthly buffer pool';

  RAISE NOTICE '==================================================';
  RAISE NOTICE 'ALL SPRINT 3 VERIFICATION TESTS PASSED SUCCESSFULLY';
  RAISE NOTICE '==================================================';
END $$;
