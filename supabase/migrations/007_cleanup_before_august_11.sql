-- ============================================================================
-- SIAGENDA Cleanup Migration: 007_cleanup_before_august_11.sql
-- Purpose: Hapus data dump/tes nomor surat sebelum tanggal 11 Agustus 2026
-- dan reset status buffer cadangan agar nomor-nomor tersebut dapat dipakai kembali.
-- ============================================================================

-- 1. Hapus semua catatan nomor agenda sebelum tanggal 11 Agustus 2026
DELETE FROM public.agenda_numbers 
WHERE tanggal_agenda < '2026-08-11';

-- 2. Kembalikan status buffer cadangan tanggal sebelum 11 Agustus 2026 menjadi 'tersedia'
-- (supaya stok nomor cadangan untuk backdate pada tanggal-tanggal tersebut dapat digunakan kembali)
UPDATE public.daily_buffers 
SET status = 'tersedia' 
WHERE tanggal < '2026-08-11';
