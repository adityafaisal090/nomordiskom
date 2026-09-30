# Design Document — MONA
Diskominfo | v1.0 | Pelengkap PRD.md

## 1. Arsitektur Sistem

```
┌────────────────────────┐      Supabase Client SDK       ┌───────────────────────────┐
│   Flutter App            │ ──────────────────────────────▶│  Supabase Project          │
│ (Android + Web)           │◀────────────────────────────── │  - Auth (Supabase Auth)     │
│  - Login                  │        (postgrest + realtime)   │  - Postgres Database        │
│  - Form Nomor Agenda       │                                  │  - RPC Functions (PL/pgSQL) │
│  - Home (list, realtime)    │                                  │  - Row Level Security (RLS) │
│  - Admin Dashboard (2 tab)   │                                  │  - pg_cron (buffer harian+bulanan) │
│  - Lonceng Notifikasi (in-app)│                                │  - Edge Function (kirim push) │
└────────────────────────┘                                  └──────────────┬────────────┘
        ▲                                                                    │ HTTP (FCM API)
        │ Push notification                                                  ▼
        └──────────────────────────────────────────────────  ┌───────────────────────┐
                                                                 │  Firebase Cloud         │
                                                                 │  Messaging (FCM)        │
                                                                 │  (project terpisah,      │
                                                                 │  di luar Supabase)        │
                                                                 └───────────────────────┘
```

**Tidak ada backend custom (Node/Express) sama sekali.** Flutter berkomunikasi langsung ke
Supabase pakai package `supabase_flutter`. Tapi ini **bukan berarti tanpa logic sisi
server** — logic penomoran yang butuh atomic transaction (anti nomor ganda) tetap WAJIB
ditulis sebagai **Postgres Function (RPC)** yang hidup di dalam database Supabase itu
sendiri. Ini beda dengan "Flutter connect langsung ke tabel tanpa logic apa pun", yang
TIDAK aman dipakai untuk counter nomor agenda. Jadi pembagiannya:
- **Boleh langsung dari Flutter** (lewat Supabase client, diproteksi RLS): SELECT untuk
  list Home, SELECT profil sendiri, SELECT/UPDATE notifikasi milik sendiri.
- **WAJIB lewat RPC Function** (bukan langsung UPDATE/INSERT dari Flutter): buat nomor
  (hari ini/backdate), edit data sebelum ACC, approve/reject, generate buffer.
- **1 pengecualian khusus untuk push notification**: karena butuh kunci rahasia (FCM
  server key) yang tidak boleh ada di Flutter, pengiriman push **wajib** lewat
  **Supabase Edge Function** — ini satu-satunya bagian di aplikasi yang butuh Edge
  Function, bukan cuma RPC biasa. Edge Function tetap bagian dari Supabase (serverless,
  bukan server custom terpisah), jadi tidak melanggar keputusan "tanpa backend custom".

## 2. Tech Stack & Alasan
| Komponen | Pilihan | Alasan |
|---|---|---|
| Frontend | Flutter | 1 codebase untuk Android + Web, cocok untuk kebutuhan akses dari luar kantor |
| Backend | **Supabase** (bukan custom backend) | Full BaaS: Auth + Postgres + Realtime + RPC + Scheduler dalam 1 platform, mempercepat development |
| Database | Supabase Postgres | Mendukung transaction + row locking (`SELECT ... FOR UPDATE`) via Postgres Function, krusial untuk mencegah nomor ganda saat akses bersamaan |
| Auth | Supabase Auth + workaround username (lihat 3.1) | Sesi otomatis persist di client, tidak perlu bikin JWT/session manual |
| Logic penomoran & aturan bisnis | Postgres Function (RPC), `SECURITY DEFINER` | Satu-satunya cara menjamin atomicity tanpa backend custom |
| Akses data | Supabase client SDK + Row Level Security (RLS) | Otorisasi per-role langsung di level database, tidak perlu middleware |
| Scheduler | `pg_cron` (extension Supabase) | Untuk generate buffer harian jam 00:00 WIB, aktifkan lewat Database → Extensions |
| Realtime | Supabase Realtime | Home list & tab admin (Pending → Disetujui) bisa auto-update tanpa refresh manual |
| State management Flutter | Provider / Riverpod (pilih salah satu, konsisten) | Sederhana, cukup untuk skala aplikasi ini |
| Sesi login Flutter | `supabase_flutter` (session persistence built-in) | Otomatis handle "tetap login sampai logout", tidak perlu `flutter_secure_storage` manual |
| Push notification | Firebase Cloud Messaging (FCM) + `firebase_messaging` (Flutter) | Satu-satunya opsi push yang wajar untuk Flutter, Supabase tidak punya layanan push sendiri |
| Pengirim push | Supabase Edge Function (Deno) | Menyimpan FCM server key dengan aman, dipicu Database Webhook saat ada notifikasi baru |
| In-app notification | Tabel `notifications` + Supabase Realtime | Riwayat notifikasi tersimpan, badge unread ter-update live tanpa refresh |

## 3. Data Model

### 3.1 `auth.users` (bawaan Supabase) + `public.profiles`
Supabase Auth mengelola akun lewat tabel bawaan `auth.users` (identifier utamanya
**email**, bukan username). Karena requirement kita login pakai **username**, dibuat
tabel tambahan `public.profiles` yang terhubung 1:1 ke `auth.users`:

| Kolom | Tipe | Keterangan |
|---|---|---|
| id | UUID PK, FK → auth.users(id) | |
| username | VARCHAR(50) UNIQUE | dipakai untuk login |
| nama | VARCHAR(100) | |
| role | VARCHAR(20) | `admin` / `operator` |
| is_active | BOOLEAN | |
| fcm_token | TEXT | token push notification (Firebase Cloud Messaging), diisi Flutter lewat RPC `update_fcm_token` — lihat section 8 |
| created_at | TIMESTAMPTZ | |

**Alur login dengan username (workaround):**
1. Flutter panggil RPC `get_email_by_username(username)` — function `SECURITY DEFINER`
   yang mencari email di `auth.users` berdasarkan `username` di `profiles`, return
   email-nya saja (tidak expose data lain). Ini supaya tabel `profiles`/`auth.users`
   tidak perlu dibuka lewat RLS biasa untuk pencarian ini.
2. Flutter panggil `supabase.auth.signInWithPassword(email: hasil_lookup, password: ...)`
   seperti biasa — sisanya (JWT, session persistence) ditangani otomatis oleh
   `supabase_flutter`.

**Pembuatan akun (admin & operator):**
Belum ada user story "admin menambah akun dari dalam app" di scope saat ini. Untuk v1,
akun **dibuat manual lewat Supabase Dashboard** oleh pengelola sistem (buat user di
Authentication → Users, lalu insert baris terkait di `profiles`). Kalau nanti perlu fitur
"tambah akun dari dalam app", itu **wajib pakai Supabase Edge Function** (butuh
`service_role key` yang tidak boleh ditaruh di client Flutter) — bukan RPC biasa.

### 3.2 `template_settings`
| Kolom | Tipe | Keterangan |
|---|---|---|
| id | SERIAL PK | |
| template_tetap | VARCHAR(100) | contoh: `35.07.315` |
| is_active | BOOLEAN | |
| updated_at | TIMESTAMPTZ | |

### 3.3 `year_counters`
Counter per **tahun + kategori** (1 baris per kombinasi tahun-kategori, bukan per tahun
saja — ini yang bikin tiap kategori punya urutan nomor sendiri-sendiri). `next_number` =
nomor agenda berikutnya yang akan dikeluarkan untuk kombinasi itu (baik untuk "hari ini"
maupun untuk generate buffer).
| Kolom | Tipe |
|---|---|
| tahun | INT |
| kategori | VARCHAR(30) |
| next_number | INT |

PK gabungan: `(tahun, kategori)`.

### 3.4 `buffer_settings`
Pengaturan jumlah buffer per kategori, bisa diubah admin. Frekuensi **tidak** bisa
diubah lewat aplikasi (bawaan sistem per kategori), kolom `frekuensi` di sini murni
informasi/referensi buat function generate buffer.
| Kolom | Tipe | Keterangan |
|---|---|---|
| kategori | VARCHAR(30) PK | `surat_keputusan` / `nota_dinas` / `surat_keluar` |
| jumlah_buffer | INT | default `5`, **bisa diubah admin** |
| frekuensi | VARCHAR(10) | `harian` (khusus surat_keluar) / `bulanan` (kategori lain) — read-only, tidak ada UI untuk mengubah ini |

Seed default:
```sql
INSERT INTO buffer_settings (kategori, jumlah_buffer, frekuensi) VALUES
  ('surat_keluar', 5, 'harian'),
  ('nota_dinas', 5, 'bulanan'),
  ('surat_keputusan', 5, 'bulanan');
```

### 3.5 `agenda_buffers`
Stok nomor cadangan per kategori + periode, digenerate otomatis oleh pg_cron (harian
untuk `surat_keluar`, bulanan untuk kategori lain).
| Kolom | Tipe | Keterangan |
|---|---|---|
| id | SERIAL PK | |
| kategori | VARCHAR(30) | |
| tahun | INT | |
| periode | DATE | **Untuk kategori harian**: tanggal aktual. **Untuk kategori bulanan**: tanggal 1 di bulan terkait (representasi periode bulan itu, mis. `2026-08-01` mewakili seluruh Agustus 2026) |
| nomor | INT | |
| status | VARCHAR(20) | `tersedia` / `terpakai` |

> Saat backdate, function pencocokan beda tergantung frekuensi kategori: kategori harian
> mencocokkan `periode = tanggal_dipilih` (persis), kategori bulanan mencocokkan
> `date_trunc('month', periode) = date_trunc('month', tanggal_dipilih)` (satu bulan yang
> sama, walau operator tetap memilih tanggal spesifik lewat kalender).

### 3.6 `buffer_generation_log`
Sama seperti sebelumnya, tapi sekarang per kategori juga (cegah generate dobel per
kategori+periode):
| Kolom | Tipe |
|---|---|
| kategori | VARCHAR(30) |
| periode | DATE |
| generated_at | TIMESTAMPTZ |

PK gabungan: `(kategori, periode)`.

### 3.7 `agenda_numbers`
Data utama nomor agenda yang sudah dikeluarkan.
| Kolom | Tipe | Keterangan |
|---|---|---|
| id | SERIAL PK | |
| tahun | INT | |
| nomor_agenda | INT | tidak bisa diedit setelah dibuat, urutannya **per kategori** |
| nomor_lengkap | TEXT | hasil format lengkap siap tampil, **ditampilkan tebal di Home** |
| kategori | VARCHAR(30) | `surat_keputusan` / `nota_dinas` / `surat_keluar` — bisa diedit sebelum ACC |
| kode_klasifikasi | VARCHAR(50) | bisa diedit sebelum ACC |
| tujuan_surat | TEXT | *(sebelumnya bernama `kepada`)* — bisa diedit sebelum ACC |
| perihal | TEXT | bisa diedit sebelum ACC |
| pemohon | VARCHAR(100) | bisa diedit sebelum ACC |
| tanggal_agenda | DATE | tidak bisa diedit setelah dibuat |
| is_backdate | BOOLEAN | |
| dibuat_oleh | UUID FK profiles(id) | |
| status_acc | VARCHAR(20) | `menunggu` / `disetujui` / `ditolak` |
| catatan_admin | TEXT | opsional, diisi saat tolak |
| diacc_oleh | UUID FK profiles(id) | |
| diacc_pada | TIMESTAMPTZ | |
| created_at | TIMESTAMPTZ | |

Unique constraint: `(tahun, kategori, nomor_agenda)` — **bukan** `(tahun, nomor_agenda)`
lagi, karena tiap kategori sekarang independen (nomor 1036 di Surat Keluar dan nomor
1036 di Nota Dinas adalah 2 baris berbeda yang sah, tidak dianggap duplikat).

> Field yang **tidak pernah** bisa diedit sejak awal dibuat: `nomor_agenda`, `tanggal_agenda`,
> `nomor_lengkap`, `tahun`, `is_backdate`.
> Field yang bisa diedit **hanya selama** `status_acc = 'menunggu'`: `kategori`,
> `kode_klasifikasi`, `tujuan_surat`, `perihal`, `pemohon`.
> Begitu `status_acc = 'disetujui'` → seluruh baris terkunci total (enforce di dalam
> RPC Function `update_agenda_draft` & lewat RLS, bukan hanya validasi di sisi Flutter).

### 3.8 `notifications`
Riwayat notifikasi (dipakai untuk in-app notification / lonceng, dan jadi pemicu push
lewat Database Webhook — lihat section 8).
| Kolom | Tipe | Keterangan |
|---|---|---|
| id | SERIAL PK | |
| user_id | UUID FK profiles(id) | penerima notifikasi |
| tipe | VARCHAR(30) | `acc` / `tolak` / `pengajuan_baru` |
| judul | TEXT | judul notifikasi |
| isi | TEXT | isi pesan |
| agenda_id | INT FK agenda_numbers(id), nullable | dipakai untuk navigasi saat notifikasi di-tap |
| is_read | BOOLEAN | default `false` |
| created_at | TIMESTAMPTZ | default `now()` |

## 4. Algoritma Penomoran (bagian paling krusial)
Semua fungsi di bawah ditulis sebagai **Postgres Function (PL/pgSQL)**, dideploy ke
Supabase lewat SQL Editor/migration, dan dipanggil dari Flutter lewat
`supabase.rpc('nama_function', {...})`. Gunakan `SECURITY DEFINER` supaya function bisa
mengubah `year_counters`/`agenda_buffers` walau client (lewat RLS) tidak diberi akses
UPDATE langsung ke tabel-tabel itu.

### 4.1 RPC `issue_today_number(...)`
```sql
CREATE OR REPLACE FUNCTION issue_today_number(
  p_kategori text, p_kode_klasifikasi text, p_tujuan_surat text,
  p_perihal text, p_pemohon text
) RETURNS agenda_numbers
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_tahun int := extract(year from (now() at time zone 'Asia/Jakarta'));
  v_nomor int;
  v_template text;
  v_row agenda_numbers;
BEGIN
  -- kunci baris counter (tahun, kategori) — INI YANG BIKIN TIAP KATEGORI PUNYA URUTAN SENDIRI
  INSERT INTO year_counters (tahun, kategori, next_number) VALUES (v_tahun, p_kategori, 1)
    ON CONFLICT (tahun, kategori) DO NOTHING;
  SELECT next_number INTO v_nomor FROM year_counters
    WHERE tahun = v_tahun AND kategori = p_kategori FOR UPDATE;
  UPDATE year_counters SET next_number = next_number + 1
    WHERE tahun = v_tahun AND kategori = p_kategori;

  SELECT template_tetap INTO v_template FROM template_settings WHERE is_active LIMIT 1;

  INSERT INTO agenda_numbers (tahun, nomor_agenda, nomor_lengkap, kategori,
    kode_klasifikasi, tujuan_surat, perihal, pemohon, tanggal_agenda, is_backdate,
    dibuat_oleh, status_acc)
  VALUES (v_tahun, v_nomor,
    p_kode_klasifikasi || ' / ' || v_nomor || ' / ' || v_template || '/' || v_tahun,
    p_kategori, p_kode_klasifikasi, p_tujuan_surat, p_perihal, p_pemohon,
    (now() at time zone 'Asia/Jakarta')::date, false, auth.uid(), 'menunggu')
  RETURNING * INTO v_row;

  -- notifikasi ke semua admin (lihat section 8)
  INSERT INTO notifications (user_id, tipe, judul, isi, agenda_id)
  SELECT p.id, 'pengajuan_baru', 'Pengajuan Nomor Baru',
    (SELECT nama FROM profiles WHERE id = auth.uid()) || ' mengajukan ' || p_kategori ||
      ' — ' || v_row.nomor_lengkap,
    v_row.id
  FROM profiles p WHERE p.role = 'admin';

  RETURN v_row;
END;
$$;
```
`FOR UPDATE` mengunci baris counter **kombinasi tahun+kategori** tsb selama transaksi
function ini berjalan → mencegah 2 request bersamaan **di kategori yang sama** mendapat
nomor yang sama (mengatasi bug "nomor ganda" / "nomor tidak berurutan"). Request di
kategori berbeda tidak saling mengunci satu sama lain (bisa diproses paralel), karena
baris counter yang dikunci berbeda per kategori. Karena seluruh isi function berjalan
dalam 1 transaksi Postgres otomatis, ini tetap atomic walau dipanggil dari client manapun
tanpa backend custom.

### 4.2 RPC `generate_buffer_for_period(p_kategori text, p_periode date)`
Function generik dipakai untuk kategori harian maupun bulanan — bedanya cuma di
`p_periode` yang dikirim & jadwal pg_cron yang memanggilnya (lihat di bawah).
```sql
CREATE OR REPLACE FUNCTION generate_buffer_for_period(p_kategori text, p_periode date)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_tahun int := extract(year from p_periode);
  v_next int;
  v_jumlah int;
BEGIN
  -- cegah generate dobel untuk kategori+periode yang sama
  IF EXISTS (SELECT 1 FROM buffer_generation_log WHERE kategori = p_kategori AND periode = p_periode) THEN
    RETURN;
  END IF;

  SELECT jumlah_buffer INTO v_jumlah FROM buffer_settings WHERE kategori = p_kategori;
  IF v_jumlah IS NULL THEN v_jumlah := 5; END IF; -- fallback kalau baris setting belum ada

  INSERT INTO year_counters (tahun, kategori, next_number) VALUES (v_tahun, p_kategori, 1)
    ON CONFLICT (tahun, kategori) DO NOTHING;
  SELECT next_number INTO v_next FROM year_counters
    WHERE tahun = v_tahun AND kategori = p_kategori FOR UPDATE;

  INSERT INTO agenda_buffers (kategori, tahun, periode, nomor, status)
  SELECT p_kategori, v_tahun, p_periode, v_next + i, 'tersedia'
  FROM generate_series(0, v_jumlah - 1) AS i;

  UPDATE year_counters SET next_number = v_next + v_jumlah
    WHERE tahun = v_tahun AND kategori = p_kategori;
  INSERT INTO buffer_generation_log (kategori, periode) VALUES (p_kategori, p_periode);
END;
$$;
```

**Jadwal pg_cron** (aktifkan extension dulu di Database → Extensions). Ada **2 jadwal
terpisah** karena frekuensinya beda per kategori:
```sql
-- (a) Kategori HARIAN (surat_keluar): tiap hari 17:00 UTC = 00:00 WIB.
-- Generate buffer untuk tanggal yang BARU SAJA berakhir (WIB).
SELECT cron.schedule(
  'generate-buffer-harian',
  '0 17 * * *',
  $$ SELECT generate_buffer_for_period('surat_keluar', (now() at time zone 'Asia/Jakarta')::date - 1); $$
);

-- (b) Kategori BULANAN (nota_dinas, surat_keputusan): tiap tanggal 1, 17:00 UTC = 00:00 WIB.
-- Generate buffer untuk BULAN yang baru saja berakhir (periode = tanggal 1 bulan itu).
SELECT cron.schedule(
  'generate-buffer-bulanan',
  '0 17 1 * *',
  $$
  SELECT generate_buffer_for_period('nota_dinas',
    date_trunc('month', (now() at time zone 'Asia/Jakarta')::date - 1)::date);
  SELECT generate_buffer_for_period('surat_keputusan',
    date_trunc('month', (now() at time zone 'Asia/Jakarta')::date - 1)::date);
  $$
);
```

### 4.3 RPC `issue_backdate_number(p_tanggal date, ...)`
```sql
CREATE OR REPLACE FUNCTION issue_backdate_number(
  p_tanggal date, p_kategori text, p_kode_klasifikasi text,
  p_tujuan_surat text, p_perihal text, p_pemohon text
) RETURNS agenda_numbers
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_frekuensi text;
  v_buffer_id int;
  v_nomor int;
  v_tahun int := extract(year from p_tanggal);
  v_template text;
  v_row agenda_numbers;
BEGIN
  SELECT frekuensi INTO v_frekuensi FROM buffer_settings WHERE kategori = p_kategori;

  IF v_frekuensi = 'harian' THEN
    SELECT id, nomor INTO v_buffer_id, v_nomor FROM agenda_buffers
      WHERE kategori = p_kategori AND periode = p_tanggal AND status = 'tersedia'
      ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;
  ELSE -- 'bulanan': cocokkan ke periode bulan yang sama, walau tanggal beda
    SELECT id, nomor INTO v_buffer_id, v_nomor FROM agenda_buffers
      WHERE kategori = p_kategori
        AND date_trunc('month', periode) = date_trunc('month', p_tanggal)
        AND status = 'tersedia'
      ORDER BY nomor ASC LIMIT 1 FOR UPDATE SKIP LOCKED;
  END IF;

  IF v_buffer_id IS NULL THEN
    RAISE EXCEPTION 'BUFFER_HABIS: Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan koordinasi lebih lanjut dengan TU';
  END IF;

  UPDATE agenda_buffers SET status = 'terpakai' WHERE id = v_buffer_id;
  SELECT template_tetap INTO v_template FROM template_settings WHERE is_active LIMIT 1;

  INSERT INTO agenda_numbers (tahun, nomor_agenda, nomor_lengkap, kategori,
    kode_klasifikasi, tujuan_surat, perihal, pemohon, tanggal_agenda, is_backdate,
    dibuat_oleh, status_acc)
  VALUES (v_tahun, v_nomor,
    p_kode_klasifikasi || ' / ' || v_nomor || ' / ' || v_template || '/' || v_tahun,
    p_kategori, p_kode_klasifikasi, p_tujuan_surat, p_perihal, p_pemohon,
    p_tanggal, true, auth.uid(), 'menunggu')
  RETURNING * INTO v_row;

  -- notifikasi ke semua admin (lihat section 8)
  INSERT INTO notifications (user_id, tipe, judul, isi, agenda_id)
  SELECT p.id, 'pengajuan_baru', 'Pengajuan Nomor Baru',
    (SELECT nama FROM profiles WHERE id = auth.uid()) || ' mengajukan ' || p_kategori ||
      ' — ' || v_row.nomor_lengkap,
    v_row.id
  FROM profiles p WHERE p.role = 'admin';

  RETURN v_row;
END;
$$;
```
Di Flutter, tangkap error dengan kode `BUFFER_HABIS` (Supabase mengembalikannya sebagai
`PostgrestException`) untuk menampilkan popup "sudah habis" sesuai prototype. Operator
**tetap memilih tanggal spesifik lewat kalender** untuk semua kategori (termasuk yang
buffernya bulanan) — function di atas yang otomatis mencocokkan ke periode yang tepat.

### 4.4 RPC `update_buffer_setting(p_kategori text, p_jumlah int)` — khusus Admin
```sql
CREATE OR REPLACE FUNCTION update_buffer_setting(p_kategori text, p_jumlah int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role text;
BEGIN
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'FORBIDDEN: hanya admin yang boleh mengubah pengaturan buffer';
  END IF;
  IF p_jumlah < 1 THEN
    RAISE EXCEPTION 'INVALID_INPUT: jumlah buffer minimal 1';
  END IF;

  UPDATE buffer_settings SET jumlah_buffer = p_jumlah WHERE kategori = p_kategori;
END;
$$;
```
Catatan: `frekuensi` sengaja tidak ada parameter untuk mengubahnya di function ini —
sesuai keputusan, frekuensi tetap (harian untuk `surat_keluar`, bulanan untuk lainnya)
dan tidak ditawarkan sebagai opsi yang bisa diubah dari UI.

### 4.5 Reset Tahunan
Karena `year_counters` berbasis primary key gabungan `(tahun, kategori)`, reset terjadi
otomatis per kategori — semua function di atas sudah menghandle
`INSERT ... ON CONFLICT DO NOTHING` untuk membuat baris tahun baru dengan
`next_number = 1` kalau belum ada. Tidak perlu proses "reset" eksplisit.

### 4.6 Format Nomor Lengkap
Sudah dirakit langsung di dalam function (lihat 4.1/4.3):
```
nomor_lengkap = kode_klasifikasi || ' / ' || nomor_agenda || ' / ' || template_tetap || '/' || tahun
```
Nomor ini yang ditampilkan **tebal** di Home (lihat 9.1/9.2) — ini murni styling di
Flutter, bukan sesuatu yang disimpan berbeda di database.

## 5. Pemanggilan dari Flutter (pengganti "API Endpoints")
Karena tidak ada backend custom, ini daftar pemanggilan Supabase yang dipakai dari Flutter
(lewat `supabase_flutter`), pengganti tabel REST endpoint sebelumnya:

| Aksi | Cara Panggil | Role | Keterangan |
|---|---|---|---|
| Login | RPC `get_email_by_username` lalu `auth.signInWithPassword` | public | lihat 3.1 |
| Logout | `auth.signOut()` | authenticated | session otomatis dihapus client |
| Cek sesi/profil aktif | `.from('profiles').select().eq('id', auth.uid())` | authenticated | dipakai cek role saat app dibuka |
| Buat nomor (hari ini) | RPC `issue_today_number(...)` | operator | lihat 4.1 |
| Buat nomor (backdate) | RPC `issue_backdate_number(...)` | operator | lihat 4.3 |
| List Home (grup bulan/tanggal) | `.from('agenda_numbers').select().order(...)` | authenticated | difilter/dikelompokkan di Flutter, RLS izinkan SELECT semua baris untuk authenticated |
| Edit sebelum ACC | RPC `update_agenda_draft(id, kategori, kode_klasifikasi, tujuan_surat, perihal, pemohon)` | operator | function menolak jika `status_acc != 'menunggu'` — nomor & tanggal tidak ada di parameter, jadi tidak mungkin diubah |
| Tab "Pending" admin | `.from('agenda_numbers').select().eq('status_acc','menunggu')` | admin | |
| Tab "Disetujui" admin | `.from('agenda_numbers').select().eq('status_acc','disetujui')` | admin | |
| Approve | RPC `approve_agenda(id)` | admin | mengunci baris (lihat 7) |
| Reject | RPC `reject_agenda(id, catatan)` | admin | |
| Realtime update Home/tab admin | `.from('agenda_numbers').stream(...)` | authenticated | biar pindah Pending→Disetujui langsung update tanpa refresh |
| Lihat pengaturan buffer | `.from('buffer_settings').select()` | admin | RLS: SELECT boleh untuk admin, lihat 7 |
| Ubah jumlah buffer per kategori | RPC `update_buffer_setting(kategori, jumlah)` | admin | lihat 4.4, cuma jumlah yang bisa diubah, bukan frekuensi |
| Daftarkan/update token push | RPC `update_fcm_token(token)` | authenticated | dipanggil saat login & saat token FCM refresh, lihat 8.2 |
| List riwayat notifikasi (lonceng) | `.from('notifications').select().eq('user_id', auth.uid())` | authenticated | RLS: cuma baris milik sendiri, lihat 8.6 |
| Realtime badge notifikasi belum dibaca | `.from('notifications').stream().eq('user_id', auth.uid())` | authenticated | lihat 8.5 |
| Tandai notifikasi terbaca | `.from('notifications').update({'is_read': true}).eq('id', id)` | authenticated | boleh langsung UPDATE (bukan RPC), RLS batasi ke baris sendiri |

> Semua RPC di atas otomatis tahu siapa pemanggilnya lewat `auth.uid()` di dalam
> function (tidak perlu dikirim manual dari Flutter) — dipakai untuk isi `dibuat_oleh`,
> `diacc_oleh`, dan pengecekan role.

## 6. Struktur Folder

```
project/
  supabase/
    migrations/       (file .sql: buat tabel, RPC function, RLS policy, pg_cron schedule)
    functions/
      send-push/       (Edge Function Deno untuk kirim push notification, lihat 8.3)
  flutter_app/
    lib/
      screens/         (login, home, form_agenda, admin_dashboard [2 tab: pending & disetujui], notifikasi)
      services/         (supabase_service.dart — wrapper pemanggilan RPC/table, fcm_service.dart)
      models/
      widgets/
```

Tidak ada folder `backend/` lagi — semua logic server-side (RPC function, RLS policy,
jadwal pg_cron) ditulis sebagai file `.sql` di `supabase/migrations/` dan dijalankan lewat
Supabase CLI (`supabase db push`) atau ditempel manual ke SQL Editor di Supabase Dashboard.

## 7. Keamanan
- Password dikelola sepenuhnya oleh Supabase Auth (hash, reset, dsb) — kita tidak pernah
  menyimpan/menangani password secara manual.
- Sesi & JWT ditangani otomatis oleh `supabase_flutter`; token tidak perlu disimpan manual.
- **Row Level Security (RLS) wajib diaktifkan di semua tabel** (`profiles`,
  `agenda_numbers`, `year_counters`, `agenda_buffers`, `buffer_settings`,
  `template_settings`). Contoh kebijakan inti:
  - `profiles`: SELECT hanya untuk baris milik sendiri (`auth.uid() = id`); tidak ada
    INSERT/UPDATE/DELETE dari client (akun dikelola manual, lihat 3.1).
  - `agenda_numbers`: SELECT diizinkan untuk semua user `authenticated` (memenuhi
    requirement "Home terlihat semua operator & admin"). **INSERT dan UPDATE langsung
    dari client DITOLAK sepenuhnya oleh RLS** — satu-satunya jalan mengubah data adalah
    lewat RPC function (`issue_today_number`, `issue_backdate_number`,
    `update_agenda_draft`, `approve_agenda`, `reject_agenda`) yang jalan sebagai
    `SECURITY DEFINER` sehingga bisa menembus RLS ini dengan aman karena logic
    validasinya sudah ketat di dalam function.
  - `year_counters`, `agenda_buffers`: tidak ada akses SELECT/INSERT/UPDATE sama sekali
    dari client biasa — murni hanya diakses lewat RPC function `SECURITY DEFINER`.
  - `buffer_settings`: SELECT diizinkan untuk `admin` saja (dipakai halaman pengaturan);
    UPDATE langsung dari client **ditolak** — wajib lewat RPC `update_buffer_setting`
    yang mengecek role di dalamnya (lihat 4.4).
  - `notifications`: lihat 8.6 — SELECT/UPDATE terbatas ke baris milik sendiri,
    INSERT/DELETE hanya lewat RPC.
- **Edge Function `send-push`** memegang `SUPABASE_SERVICE_ROLE_KEY` dan kredensial FCM
  — keduanya disimpan sebagai **secret di environment Edge Function** (`supabase secrets
  set`), TIDAK PERNAH ada di kode Flutter yang di-build ke APK/Web (yang bisa dibongkar
  siapa saja). Ini prinsip yang sama seperti alasan pembuatan akun admin/operator wajib
  lewat Edge Function (lihat 3.1), bukan langsung dari client.
- Pengecekan role (admin vs operator) dilakukan **di dalam setiap RPC function**
  (query `role` dari `profiles` berdasar `auth.uid()`), bukan di sisi Flutter — supaya
  operator tidak bisa memanggil `approve_agenda` walau tahu nama function-nya.
- Validasi status `disetujui` (data terkunci) dicek ulang di dalam
  `update_agenda_draft` — jangan mengandalkan validasi di sisi Flutter saja.

## 8. Notifikasi

### 8.1 RPC `approve_agenda(p_id int)` & `reject_agenda(p_id int, p_catatan text)`
Ini function yang sebelumnya cuma disebut nama di section 5, sekarang ditulis lengkap
karena keduanya juga jadi tempat memicu notifikasi ke operator:
```sql
CREATE OR REPLACE FUNCTION approve_agenda(p_id int)
RETURNS agenda_numbers
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role text;
  v_row agenda_numbers;
BEGIN
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'FORBIDDEN: hanya admin yang boleh meng-ACC';
  END IF;

  UPDATE agenda_numbers
  SET status_acc = 'disetujui', diacc_oleh = auth.uid(), diacc_pada = now()
  WHERE id = p_id AND status_acc = 'menunggu'
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND_OR_LOCKED: data tidak ditemukan atau sudah diproses sebelumnya';
  END IF;

  INSERT INTO notifications (user_id, tipe, judul, isi, agenda_id)
  VALUES (v_row.dibuat_oleh, 'acc', 'Nomor Agenda Disetujui',
    'Nomor agenda Anda ' || v_row.nomor_lengkap || ' telah disetujui.', v_row.id);

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION reject_agenda(p_id int, p_catatan text DEFAULT NULL)
RETURNS agenda_numbers
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role text;
  v_row agenda_numbers;
BEGIN
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'FORBIDDEN: hanya admin yang boleh menolak';
  END IF;

  UPDATE agenda_numbers
  SET status_acc = 'ditolak', catatan_admin = p_catatan,
      diacc_oleh = auth.uid(), diacc_pada = now()
  WHERE id = p_id AND status_acc = 'menunggu'
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'NOT_FOUND_OR_LOCKED: data tidak ditemukan atau sudah diproses sebelumnya';
  END IF;

  INSERT INTO notifications (user_id, tipe, judul, isi, agenda_id)
  VALUES (v_row.dibuat_oleh, 'tolak', 'Nomor Agenda Ditolak',
    'Nomor agenda Anda ' || v_row.nomor_lengkap || ' ditolak.' ||
      CASE WHEN p_catatan IS NOT NULL THEN ' Catatan: ' || p_catatan ELSE '' END,
    v_row.id);

  RETURN v_row;
END;
$$;
```

### 8.2 RPC `update_fcm_token(p_token text)`
Dipanggil Flutter setiap kali dapat/refresh token FCM (saat login & setiap event token
refresh dari `firebase_messaging`):
```sql
CREATE OR REPLACE FUNCTION update_fcm_token(p_token text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE profiles SET fcm_token = p_token WHERE id = auth.uid();
END;
$$;
```

### 8.3 Edge Function `send-push` (dipicu tiap ada baris baru di `notifications`)
```ts
// supabase/functions/send-push/index.ts
import { createClient } from 'jsr:@supabase/supabase-js@2';

Deno.serve(async (req) => {
  const { record } = await req.json(); // baris `notifications` yang baru di-insert

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, // aman: cuma ada di environment Edge Function, TIDAK di Flutter
  );

  const { data: profile } = await supabase
    .from('profiles').select('fcm_token').eq('id', record.user_id).single();

  if (!profile?.fcm_token) return new Response('no fcm token', { status: 200 });

  await fetch(`https://fcm.googleapis.com/v1/projects/${Deno.env.get('FCM_PROJECT_ID')}/messages:send`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${await getFcmAccessToken()}`, // lihat catatan di bawah
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token: profile.fcm_token,
        notification: { title: record.judul, body: record.isi },
        data: { agenda_id: String(record.agenda_id ?? '') },
      },
    }),
  });

  return new Response('ok', { status: 200 });
});
```
> Catatan: FCM API v1 (yang terbaru, bukan legacy server key yang sudah deprecated
> Google) butuh OAuth2 access token dari **service account** Firebase, bukan cuma 1
> string key statis. Simpan JSON service account sebagai secret di Supabase Edge
> Function (`supabase secrets set`), generate access token saat runtime di dalam
> function (`getFcmAccessToken()` di atas). Detail implementasi persisnya diserahkan ke
> AI VSCode saat coding — poin pentingnya: kredensial ini **tidak boleh** pernah ada di
> kode Flutter.

### 8.4 Pemicu: Database Webhook
Supaya `send-push` otomatis terpanggil tiap ada baris baru di `notifications`, di
Supabase Dashboard: **Database → Webhooks → Create a new webhook**:
- Table: `notifications`, Event: `INSERT`
- Type: **Supabase Edge Function**, target: `send-push`

Ini konfigurasi lewat Dashboard (tidak perlu kode tambahan). Alternatif kalau mau
semuanya dalam bentuk migration `.sql` (tanpa klik Dashboard): pakai extension `pg_net`
dengan trigger `AFTER INSERT ON notifications` yang memanggil Edge Function lewat
`net.http_post(...)` — hasil akhirnya sama, tinggal pilih salah satu.

### 8.5 In-App Notification (Lonceng)
- Flutter subscribe Realtime ke `.from('notifications').stream().eq('user_id', auth.uid())`
  → badge jumlah `is_read = false` ter-update live tanpa refresh.
- Tap notifikasi → set `is_read = true` (boleh langsung UPDATE dari Flutter, RLS
  mengizinkan user update baris miliknya sendiri, lihat 8.6) + navigasi ke detail surat
  terkait pakai `agenda_id`.

### 8.6 RLS `notifications`
- SELECT: hanya baris milik sendiri (`user_id = auth.uid()`).
- UPDATE: hanya baris milik sendiri, dipakai buat tandai `is_read` (tidak perlu RPC
  khusus untuk ini, risikonya rendah — beda dengan `agenda_numbers` yang aturan
  editnya kompleks).
- INSERT/DELETE: **ditolak** dari client — hanya RPC (`issue_today_number`,
  `issue_backdate_number`, `approve_agenda`, `reject_agenda`) yang boleh insert, lewat
  `SECURITY DEFINER`.

## 9. Referensi UI/UX (dari Prototype)
Gambar wireframe asli ada di `docs/reference-ui/`. AI coding assistant yang mengerjakan
tampilan Flutter **wajib melihat gambar-gambar ini** sebagai acuan visual (bukan cuma
teks di bawah), supaya hasilnya semirip mungkin dengan prototype.

### 9.1 Gaya Visual Umum (berlaku di semua layar)
> **Update palet warna**: prototype awal (section 9.2 di bawah) memakai tema gelap
> (dark theme). Ini **sudah diganti** jadi tema **biru + putih** (medium blue, bukan
> biru tua/gelap maupun biru muda pastel). Bacaan layout/struktur di 9.2 tetap berlaku
> (posisi elemen, jenis komponen), tapi **abaikan warna hitam/gelap yang disebutkan di
> situ** — ganti semua background gelap jadi putih/biru sesuai token warna di bawah.

**Token warna (referensi untuk implementasi, sesuaikan nama variabel dengan konvensi
Flutter/Material yang dipakai):**
| Token | Warna | Dipakai untuk |
|---|---|---|
| `primary` | Biru medium — mis. `#2F6FED` / `#3B7DEB` (bisa disesuaikan, yang penting tidak terlalu gelap/navy dan tidak terlalu terang/pastel) | AppBar, tombol utama, ikon aktif, badge, highlight |
| `surface` | Putih `#FFFFFF` | Background utama layar, card, modal |
| `surface-alt` | Biru sangat muda — mis. `#EAF1FD` | Background halaman (bukan putih polos, sedikit tint biru) supaya beda dari card yang putih |
| `text-primary` | Abu gelap/hitam lembut — mis. `#1A1A1A` | Teks utama di atas putih |
| `text-on-primary` | Putih `#FFFFFF` | Teks di atas elemen berwarna primary |

- **Watermark peta Indonesia** tetap dipakai sebagai elemen dekoratif, tapi ganti jadi
  versi biru muda/transparan (bukan abu-abu gelap) supaya cocok di atas background
  terang.
- **Branding**: logo/lambang instansi + nama aplikasi "MONA" (bisa tambah tagline
  "Monitoring Nomor Agenda") di header Home, tetap dengan warna `primary` (biru) sebagai
  aksen, bukan hitam.
- **Tombol**: tetap pill-shaped (sudut sangat membulat), sekarang **biru (`primary`)
  dengan teks putih** untuk aksi utama, atau outline biru dengan teks biru untuk aksi
  sekunder — bukan hitam/putih polos lagi.
- **Input field**: pill-shaped dengan ikon di kiri, border tipis biru muda, placeholder
  abu-abu, background putih.
- **Kartu list surat**: putih dengan border/shadow tipis (karena background halaman
  sekarang juga terang, card putih perlu pembeda halus — border 1px biru muda atau
  shadow ringan), ikon dokumen di kiri (warna biru), nama pemohon kecil di pojok kanan
  atas card, judul kategori tebal, **nomor lengkap ditampilkan tebal** (sesuai PRD 7.6).
- **Modal/popup**: card putih rounded dengan overlay gelap transparan tipis di
  belakangnya (overlay-nya tetap boleh gelap walau tema utama terang, supaya modal
  tetap menonjol), judul bold, tombol aksi pakai warna `primary`.

### 9.2 Deskripsi per Layar (acuan LAYOUT/STRUKTUR — warna sudah diganti, lihat 9.1)

**1. Login** — `01-login.png`
Header hitam dengan watermark peta Indonesia + judul "Login" & subjudul "Please Sign in
to Continue". Toggle pill "Login" / "Sign Up". Form: input Username (ikon user), input
Password (ikon gembok + toggle show/hide), switch "Reminder me", tombol besar "Login",
teks kecil "Don't have account? Sign up" di bawah *(khusus MONA: sign up tidak perlu
diaktifkan, akun dibuat manual oleh admin — abaikan bagian ini atau sembunyikan)*.

**2. Home Operator** — `02-home-operator.png`
Header: hamburger menu (kiri) + logo & nama instansi (tengah/kiri). Watermark peta
Indonesia di bawah header. Tombol **+** melayang berbentuk lingkaran putih di tengah
(shortcut ke halaman "Buat Nomor Surat" — ini pengganti tombol biasa). Di bawahnya: 3
pill selector **Tahun / Bulan / Tanggal** (mis. "2026" / "July" / "18") sebagai navigasi
cepat ke pengelompokan per bulan→tanggal (sesuai requirement 7.6). Search bar + tombol
"sort by". Judul section "Nomor surat yang tersedia". List kartu surat (kategori, nomor
lengkap **ditampilkan tebal/bold**, nama pemohon).

**3. Form Buat Nomor Surat** — `03-form-buat-nomor.png`
Back arrow + judul "Buat Nomor Surat". Field urut: **Pilih Kategori** (dropdown),
**Masukkan Kode Klasifikasinya** (placeholder "Angka"), **Masukkan Perihal** (placeholder
"Perihal Apa"), **Masukkan Tujuan Surat** *(di prototype masih tertulis "Masukkan Kepada
Siapa", label field ini sudah diganti — isian tetap teks bebas)*, **Masukkan Pemohon
nomor** (placeholder "Nama"). Tombol "BUAT" di bawah label "Buat Nomor Agenda".

**4. Popup Pilih Waktu** — `04-popup-pilih-waktu.png`
Muncul setelah tombol "BUAT" ditekan. Modal: judul "Ingin Membuat Nomor Surat Untuk
Kapan?" + 3 opsi (tampil sebagai list teks, bukan tombol besar): **Hari Ini**, **Hari
Lain**, **Kembali**.

**5. Popup Pilih Tanggal** — `05-popup-pilih-tanggal.png`
Muncul kalau pilih "Hari Lain". Modal judul "Pilih Tanggal" + kalender bulan penuh
(Su–Sa) + tombol "OKE" di kanan bawah.

**6. Popup Hasil Nomor** — `06-popup-hasil-nomor.png`
Dua varian (tampil salah satu saja sesuai hasil, digambar berdampingan di prototype
hanya untuk perbandingan):
- **Berhasil**: "Anda mendapatkan nomor surat" + nomor lengkap + ikon centang hijau.
- **Gagal (stok habis)**: "Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan
  koordinasi lebih lanjut dengan TU" + ikon silang merah + teks kecil "Kembali ke
  halaman sebelumnya". *(Catatan: pesan di prototype ini beda kalimat dengan yang
  dipakai di PRD "arahkan ke tanggal berikutnya" — pilih salah satu kalimat final saat
  implementasi, lihat 9.3 di bawah.)*

**7. Home Admin** — `07-home-admin.png`
Layout sama seperti Home Operator (header, date selector, search+sort, list kartu), tapi
**tanpa tombol + mengambang** (admin tidak membuat nomor). Saat sebuah kartu di-tap, kartu
tersebut **expand di tempat** menampilkan detail (Perihal, Tujuan Surat, Pemohon Nomor) +
tombol "ACC" di kartu itu juga (bukan pindah halaman terpisah). *(Di prototype masih
tertulis "Yth.", label ini sudah diganti jadi "Tujuan Surat".)*

**8. Popup Konfirmasi ACC** — `08-popup-konfirmasi-acc.png`
Modal judul "Anda Yakin meng-Konfirmasi surat ini?" + penjelasan "jika anda klik Lanjut
maka semua Informasi dalam surat tersebut tidak dapat dirubah" + opsi **Lanjut** /
**Kembali**.

### 9.3 Pesan Stok Buffer Habis (Sudah Final)
Sempat ada 2 versi kalimat berbeda antara draft awal PRD dan prototype — **sudah
diputuskan pakai versi prototype**, dan versi ini sudah diterapkan di PRD 7.2 dan RPC
`issue_backdate_number` (4.3):
> "Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan koordinasi lebih lanjut
> dengan TU" — user kembali manual ke halaman sebelumnya (tidak ada auto-redirect ke
> tanggal lain).

### 9.4 Halaman Admin — 2 Tab (Pending & Disetujui)
Prototype yang di-upload belum menggambarkan pemisahan 2 tab (Pending/Disetujui) secara
eksplisit — gambar `07-home-admin.png` menampilkan 1 list saja. Penambahan 2 tab adalah
hasil klarifikasi Anda di luar prototype (lihat PRD 7.7). Saat implementasi, style tab
(warna aktif/nonaktif, posisi di atas search bar, dsb) tetap ikuti gaya visual 9.1 di
atas, karena belum ada acuan gambar spesifik untuk itu.

### 9.5 Halaman Pengaturan Buffer (Admin) — Belum Ada di Prototype
Prototype belum menggambarkan halaman ini sama sekali (fitur baru: admin atur jumlah
buffer per kategori, lihat PRD 7.3.1). Saat implementasi, ikuti gaya visual umum di 9.1
(dark theme, pill-shaped input/button). Isinya minimal: 3 baris (satu per kategori) berisi
nama kategori, frekuensi (read-only, tampil sebagai teks/badge saja — bukan input), dan
input angka jumlah buffer yang bisa diedit + tombol simpan.

## 10. Rencana Deployment
- **Database & backend logic**: 1 Supabase Project (pilih region terdekat, mis.
  Singapore) — cukup buat via Supabase Dashboard, tidak perlu setup VPS/server sendiri
  lagi untuk database/backend.
  > Catatan kebijakan: data instansi pemerintah biasanya perlu dicek dulu terkait
  > PDN/PSE — karena Supabase adalah layanan cloud pihak ketiga (server di luar
  > Indonesia kecuali pakai self-hosted Supabase), sebaiknya dikonfirmasi ke bagian
  > kebijakan/keamanan internal Diskominfo apakah ini diperbolehkan untuk data yang
  > akan disimpan, sebelum lanjut ke production.
- Aktifkan extension **pg_cron** lewat Database → Extensions untuk jadwal generate
  buffer — **ada 2 jadwal terpisah**: harian (khusus `surat_keluar`) dan bulanan
  (`nota_dinas` & `surat_keputusan`), lihat 4.2.
- Jalankan seluruh file `.sql` di `supabase/migrations/` (tabel, RPC function, RLS
  policy) lewat Supabase CLI (`supabase db push`) atau tempel manual ke SQL Editor.
- Environment yang perlu disimpan di Flutter (`.env` atau `--dart-define`):
  `SUPABASE_URL`, `SUPABASE_ANON_KEY` (anon key aman ditaruh di client karena semua
  proteksi ada di RLS + RPC, bukan di key ini).
- **Setup Firebase untuk push notification** (komponen baru, di luar Supabase):
  1. Buat project Firebase baru (gratis, tier Spark cukup untuk skala aplikasi ini).
  2. Aktifkan Firebase Cloud Messaging, daftarkan app Android/iOS/Web di project itu,
     unduh `google-services.json` (Android) / config Web, taruh sesuai struktur project
     Flutter standar.
  3. Buat service account key (JSON) dari Firebase Console → Project Settings →
     Service Accounts, dipakai Edge Function untuk otentikasi ke FCM API v1 (lihat 8.3).
  4. Deploy Edge Function: `supabase functions deploy send-push`, lalu set secret:
     `supabase secrets set FCM_PROJECT_ID=... ` dan taruh isi JSON service account
     sebagai secret juga (nama terserah, dipakai di dalam kode function).
  5. Setup Database Webhook (lihat 8.4) supaya Edge Function otomatis terpanggil.
- Flutter Web di-build (`flutter build web`) dan di-hosting terpisah (mis. Vercel/
  Netlify/Firebase Hosting) karena Supabase tidak menyediakan static hosting untuk
  Flutter Web; Flutter mobile didistribusikan sebagai APK internal (belum perlu ke
  Play Store untuk v1).
