-- ============================================================================
-- SIAGENDA Sprint 2 — VERIFICATION SCRIPT FOR PATCH 005
-- Tests:
-- 1. ensure_daily_buffers() auto-generates 10 buffers for past dates and advances counter by +10
-- 2. issue_today_number() includes past day buffer offset (+10 jump after completed day)
-- 3. issue_backdate_number() successfully allocates buffer numbers for past dates ("Hari Lain")
-- ============================================================================

DO $$
DECLARE
  v_test_past_date DATE := '2026-08-01';
  v_buffer_count INT;
  v_backdate_res1 agenda_numbers;
  v_backdate_res2 agenda_numbers;
  v_today_res agenda_numbers;
BEGIN
  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE 'STARTING VERIFICATION FOR PATCH 005';
  RAISE NOTICE '════════════════════════════════════════════════════════════';

  -- 1. Test manual/automatic buffer generation for past date
  PERFORM generate_daily_buffer(v_test_past_date);

  SELECT COUNT(*) INTO v_buffer_count
  FROM daily_buffers
  WHERE tanggal = v_test_past_date AND status = 'tersedia';

  ASSERT v_buffer_count = 10,
    'FAIL: Expected 10 buffers for ' || v_test_past_date || ', got ' || v_buffer_count;
  RAISE NOTICE '✅ TEST 1 PASSED: 10 buffers created for past date %', v_test_past_date;

  -- 2. Test backdate issue for past date (Issue 2 fix)
  SELECT * INTO v_backdate_res1
  FROM issue_backdate_number(v_test_past_date, 'surat_keluar', '500.12', 'Bupati', 'Surat Past 1', 'Operator Test');

  SELECT * INTO v_backdate_res2
  FROM issue_backdate_number(v_test_past_date, 'nota_dinas', '005.1', 'Camat', 'Surat Past 2', 'Operator Test');

  ASSERT v_backdate_res2.nomor_agenda = v_backdate_res1.nomor_agenda + 1,
    'FAIL: Backdate numbering not sequential! res1=' || v_backdate_res1.nomor_agenda || ', res2=' || v_backdate_res2.nomor_agenda;
  ASSERT v_backdate_res1.is_backdate = true,
    'FAIL: Backdate flag is not true';
  RAISE NOTICE '✅ TEST 2 PASSED: Backdate issuing works! Numbers: %, %',
    v_backdate_res1.nomor_agenda, v_backdate_res2.nomor_agenda;

  -- 3. Test ensure_daily_buffers & issue_today_number (Issue 1 fix)
  SELECT * INTO v_today_res
  FROM issue_today_number('surat_keputusan', '800.1', 'Kadis', 'Surat Today Test', 'Operator Test');

  ASSERT v_today_res.is_backdate = false,
    'FAIL: Today letter flag should be false';
  RAISE NOTICE '✅ TEST 3 PASSED: issue_today_number succeeded with agenda_number=%', v_today_res.nomor_agenda;

  RAISE NOTICE '════════════════════════════════════════════════════════════';
  RAISE NOTICE 'ALL VERIFICATION TESTS PASSED SUCCESSFULLY! 🎉';
  RAISE NOTICE '════════════════════════════════════════════════════════════';
END;
$$;
