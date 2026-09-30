-- SIAGENDA — SQLite Initial Schema Migration
-- All 5 tables from design.md §3

-- 3.1 users
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    nama TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'operator')),
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

-- 3.2 template_settings
CREATE TABLE IF NOT EXISTS template_settings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    template_tetap TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    updated_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

-- 3.3 year_counters (per-category counter)
CREATE TABLE IF NOT EXISTS year_counters (
    tahun INTEGER NOT NULL,
    kategori TEXT NOT NULL CHECK (kategori IN ('surat_keputusan', 'nota_dinas', 'surat_keluar')),
    next_number INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (tahun, kategori)
);

-- 3.4 buffer_settings
CREATE TABLE IF NOT EXISTS buffer_settings (
    kategori TEXT PRIMARY KEY CHECK (kategori IN ('surat_keputusan', 'nota_dinas', 'surat_keluar')),
    jumlah_buffer INTEGER NOT NULL DEFAULT 5 CHECK (jumlah_buffer > 0),
    frekuensi TEXT NOT NULL CHECK (frekuensi IN ('harian', 'bulanan')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

-- 3.5 daily_buffers
CREATE TABLE IF NOT EXISTS daily_buffers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tanggal TEXT NOT NULL,
    bulan INTEGER,
    tahun INTEGER NOT NULL,
    kategori TEXT NOT NULL DEFAULT 'surat_keluar',
    frekuensi TEXT NOT NULL DEFAULT 'harian',
    nomor INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'tersedia' CHECK (status IN ('tersedia', 'terpakai'))
);

-- 3.6 agenda_numbers
CREATE TABLE IF NOT EXISTS agenda_numbers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tahun INTEGER NOT NULL,
    nomor_agenda INTEGER NOT NULL,
    nomor_lengkap TEXT NOT NULL,
    kategori TEXT NOT NULL CHECK (kategori IN ('surat_keputusan', 'nota_dinas', 'surat_keluar')),
    kode_klasifikasi TEXT NOT NULL,
    tujuan_surat TEXT NOT NULL,
    perihal TEXT NOT NULL,
    pemohon TEXT NOT NULL,
    tanggal_agenda TEXT NOT NULL,
    is_backdate INTEGER NOT NULL DEFAULT 0,
    dibuat_oleh INTEGER NOT NULL REFERENCES users(id),
    status_acc TEXT NOT NULL DEFAULT 'menunggu' CHECK (status_acc IN ('menunggu', 'disetujui', 'ditolak')),
    catatan_admin TEXT,
    diacc_oleh INTEGER REFERENCES users(id),
    diacc_pada TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_agenda_numbers_status ON agenda_numbers(status_acc);
CREATE INDEX IF NOT EXISTS idx_agenda_numbers_tanggal ON agenda_numbers(tanggal_agenda);
CREATE INDEX IF NOT EXISTS idx_agenda_numbers_tahun ON agenda_numbers(tahun);
CREATE INDEX IF NOT EXISTS idx_daily_buffers_tanggal ON daily_buffers(tanggal, status);

-- Seed default template (35.07.315) if empty
INSERT OR IGNORE INTO template_settings (id, template_tetap, is_active)
VALUES (1, '35.07.315', 1);

-- Seed buffer_settings defaults
INSERT OR IGNORE INTO buffer_settings (kategori, jumlah_buffer, frekuensi) VALUES
  ('surat_keluar', 5, 'harian'),
  ('nota_dinas', 5, 'bulanan'),
  ('surat_keputusan', 5, 'bulanan');

-- Seed year counter for current year
INSERT OR IGNORE INTO year_counters (tahun, kategori, next_number) VALUES
  (cast(strftime('%Y', 'now') as integer), 'surat_keluar', 1),
  (cast(strftime('%Y', 'now') as integer), 'nota_dinas', 1),
  (cast(strftime('%Y', 'now') as integer), 'surat_keputusan', 1);

