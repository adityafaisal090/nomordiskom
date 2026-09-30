-- ============================================================================
-- SIAGENDA Sprint 2 — VERIFICATION SCRIPT
-- Run in Supabase SQL Editor AFTER 003_sprint2_fixes.sql
-- Tests: sequential numbering, buffer generation, backdate, RLS protection
-- ============================================================================

-- ════════════════════════════════════════════════════════════
-- TEST 1: issue_today_number — sequential numbering
-- Expected: nomor_agenda increments by 1 each call, no gaps
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  r1 agenda_numbers;
  r2 agenda_numbers;
  r3 agenda_numbers;
BEGIN
  -- Call 3 times sequentially
  SELECT * INTO r1 FROM issue_today_number('surat_keluar', '500.12.8.2', 'Kepala Dinas', 'Test Sequential 1', 'Operator Test');
  SELECT * INTO r2 FROM issue_today_number('nota_dinas', '005.3', 'Sekretaris', 'Test Sequential 2', 'Operator Test');
  SELECT * INTO r3 FROM issue_today_number('surat_keputusan', '800.1.4', 'Kepala Bidang', 'Test Sequential 3', 'Operator Test');

  -- Verify sequential
  ASSERT r2.nomor_agenda = r1.nomor_agenda + 1,
    'FAIL: nomor_agenda not sequential! r1=' || r1.nomor_agenda || ' r2=' || r2.nomor_agenda;
  ASSERT r3.nomor_agenda = r2.nomor_agenda + 1,
    'FAIL: nomor_agenda not sequential! r2=' || r2.nomor_agenda || ' r3=' || r3.nomor_agenda;

  RAISE NOTICE '✅ TEST 1 PASSED: Sequential numbering works. Numbers: %, %, %',
    r1.nomor_agenda, r2.nomor_agenda, r3.nomor_agenda;
END;
$$;


-- ════════════════════════════════════════════════════════════
-- TEST 2: generate_daily_buffer — creates 10 buffers
-- Expected: 10 rows with status 'tersedia' for the given date
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_count int;
  v_test_date date := '2026-08-03';
BEGIN
  -- Generate buffer for test date
  PERFORM generate_daily_buffer(v_test_date);

  -- Count buffers
  SELECT COUNT(*) INTO v_count FROM daily_buffers WHERE tanggal = v_test_date AND status = 'tersedia';

  ASSERT v_count = 10,
    'FAIL: Expected 10 buffers, got ' || v_count;

  RAISE NOTICE '✅ TEST 2 PASSED: 10 buffers generated for %', v_test_date;
END;
$$;


-- ════════════════════════════════════════════════════════════
-- TEST 3: generate_daily_buffer — idempotent (no duplicates)
-- Expected: Calling again for same date does nothing
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_count_before int;
  v_count_after int;
  v_test_date date := '2026-08-03';
BEGIN
  SELECT COUNT(*) INTO v_count_before FROM daily_buffers WHERE tanggal = v_test_date;

  -- Call again — should be no-op
  PERFORM generate_daily_buffer(v_test_date);

  SELECT COUNT(*) INTO v_count_after FROM daily_buffers WHERE tanggal = v_test_date;

  ASSERT v_count_before = v_count_after,
    'FAIL: Duplicate generation! Before=' || v_count_before || ' After=' || v_count_after;

  RAISE NOTICE '✅ TEST 3 PASSED: Idempotent — no duplicate buffers';
END;
$$;


-- ════════════════════════════════════════════════════════════
-- TEST 4: issue_backdate_number — takes 1 buffer
-- Expected: Returns valid row, buffer count decreases by 1
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_available_before int;
  v_available_after int;
  v_result agenda_numbers;
  v_test_date date := '2026-08-03';
BEGIN
  SELECT COUNT(*) INTO v_available_before FROM daily_buffers
    WHERE tanggal = v_test_date AND status = 'tersedia';

  SELECT * INTO v_result FROM issue_backdate_number(v_test_date, 'surat_keluar', '500.1', 'Kepala Dinas', 'Test Backdate', 'Operator Test');

  SELECT COUNT(*) INTO v_available_after FROM daily_buffers
    WHERE tanggal = v_test_date AND status = 'tersedia';

  ASSERT v_result.is_backdate = true,
    'FAIL: is_backdate should be true';
  ASSERT v_available_after = v_available_before - 1,
    'FAIL: Available buffers should decrease by 1. Before=' || v_available_before || ' After=' || v_available_after;

  RAISE NOTICE '✅ TEST 4 PASSED: Backdate number issued. Nomor: %, Available left: %',
    v_result.nomor_agenda, v_available_after;
END;
$$;


-- ════════════════════════════════════════════════════════════
-- TEST 5: issue_backdate_number — buffer habis after 10 uses
-- Generate fresh buffer for a new date, exhaust all 10, then verify error
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_test_date date := '2026-08-01';
  v_result agenda_numbers;
  i int;
  v_error_caught boolean := false;
BEGIN
  -- Generate buffer for test date
  PERFORM generate_daily_buffer(v_test_date);

  -- Use all 10 buffers
  FOR i IN 1..10 LOOP
    SELECT * INTO v_result FROM issue_backdate_number(v_test_date, 'surat_keluar', '500.1', 'Kepala', 'Exhaust Test ' || i, 'Tester');
  END LOOP;

  -- 11th call should fail
  BEGIN
    SELECT * INTO v_result FROM issue_backdate_number(v_test_date, 'surat_keluar', '500.1', 'Kepala', 'Should Fail', 'Tester');
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%BUFFER_HABIS%' OR SQLERRM LIKE '%Sudah Habis%' THEN
      v_error_caught := true;
    ELSE
      RAISE EXCEPTION 'FAIL: Wrong error message: %', SQLERRM;
    END IF;
  END;

  ASSERT v_error_caught = true,
    'FAIL: Expected BUFFER_HABIS error on 11th call but no error was raised';

  RAISE NOTICE '✅ TEST 5 PASSED: Buffer exhaustion correctly raises BUFFER_HABIS error';
END;
$$;


-- ════════════════════════════════════════════════════════════
-- TEST 6: Backdate to date with NO buffer at all
-- Expected: Error (no buffer exists)
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_result agenda_numbers;
  v_error_caught boolean := false;
  v_test_date date := '2026-07-15'; -- Never generated buffer
BEGIN
  BEGIN
    SELECT * INTO v_result FROM issue_backdate_number(v_test_date, 'surat_keluar', '500.1', 'Kepala', 'No Buffer Test', 'Tester');
  EXCEPTION WHEN OTHERS THEN
    v_error_caught := true;
    RAISE NOTICE 'Error message: %', SQLERRM;
  END;

  ASSERT v_error_caught = true,
    'FAIL: Expected error for date with no buffer';

  RAISE NOTICE '✅ TEST 6 PASSED: Backdate to date without buffer correctly raises error';
END;
$$;


-- ════════════════════════════════════════════════════════════
-- SUMMARY: Check all generated data
-- ════════════════════════════════════════════════════════════
SELECT '--- agenda_numbers ---' AS section;
SELECT id, nomor_agenda, nomor_lengkap, kategori, tanggal_agenda, is_backdate, status_acc
FROM agenda_numbers ORDER BY id;

SELECT '--- year_counters ---' AS section;
SELECT * FROM year_counters;

SELECT '--- daily_buffers summary ---' AS section;
SELECT tanggal, COUNT(*) FILTER (WHERE status = 'tersedia') AS tersedia,
       COUNT(*) FILTER (WHERE status = 'terpakai') AS terpakai
FROM daily_buffers GROUP BY tanggal ORDER BY tanggal;

SELECT '--- buffer_generation_log ---' AS section;
SELECT * FROM buffer_generation_log ORDER BY tanggal;


-- ════════════════════════════════════════════════════════════
-- CLEANUP (optional — uncomment to remove test data)
-- ════════════════════════════════════════════════════════════
-- DELETE FROM agenda_numbers WHERE perihal LIKE 'Test%' OR perihal LIKE 'Exhaust Test%' OR perihal LIKE 'No Buffer Test';
-- DELETE FROM daily_buffers WHERE tanggal IN ('2026-08-01', '2026-08-03');
-- DELETE FROM buffer_generation_log WHERE tanggal IN ('2026-08-01', '2026-08-03');
