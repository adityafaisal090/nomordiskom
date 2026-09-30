# MONA — Monitoring Nomor Agenda (Diskominfo)

Aplikasi mobile berbasis Flutter dan backend Supabase (PostgreSQL + Realtime + Edge Functions) untuk digitalisasi, otomatisasi, dan monitoring penomoran agenda persuratan dinas pada Dinas Komunikasi dan Informatika (Diskominfo) Pemerintah Kota Malang.

---

## 📋 Daftar Fitur Utama

1. **Autentikasi & Otorisasi Berbasis Peran (RBAC)**:
   - **Operator**: Membuat nomor agenda hari ini (*today*) dan tanggal lampau (*backdate*), melihat riwayat surat miliknya, menerima notifikasi push & in-app saat surat disetujui/ditolak.
   - **Admin**: Dashboard 2-tab (*Belum ACC* & *Sudah ACC*), verifikasi/persetujuan (*Approval/Rejection*) pengajuan nomor agenda, pengaturan batas buffer cadangan (*daily & monthly*), inspeksi & generate buffer manual untuk tanggal tertentu.
2. **Penomoran Agenda Otomatis & Aman dari Race Condition**:
   - Transaksi database dengan *row-level locking* (`FOR UPDATE`) pada sequence tahunan.
   - Format penomoran standar dinas: `{Kode Klasifikasi} / {Nomor Urut} / 35.73.404 / {Tahun}` (Surat Keluar) dan varian Nota Dinas & Surat Keputusan.
3. **Mekanisme Buffer Cadangan Tanggal (Backdate Protection)**:
   - Cadangan nomor otomatis per periode (harian untuk Surat Keluar, bulanan untuk Nota Dinas & SK).
   - Pengaturan buffer fleksibel oleh Admin melalui RPC `update_buffer_setting` & antarmuka aplikasi.
4. **Push Notification Realtime & FCM v1**:
   - Database Webhook / Trigger memanggil Supabase Edge Function `send-push`.
   - Menggunakan FCM HTTP v1 API dengan Service Account OAuth2 token.
   - Format notifikasi dual payload: `isi_push` (ringkas untuk status bar) & `isi` (lengkap untuk in-app notification center).
   - Penanganan izin Android 13+ (`POST_NOTIFICATIONS`), icon status bar monochrome (`@drawable/ic_notification`), dan notification channel khusus (`mona_default_channel`).
5. **Desain Antarmuka Premium (Design System 9.1)**:
   - Palette warna Biru & Putih (`#2F6FED`, `#EAF1FD`, `#FFFFFF`, `#1A1A1A`).
   - Tipografi modern Poppins, kartu data elegan dengan penomoran berbayang jelas, dan transisi halus.

---

## 🏗️ Arsitektur & Teknologi

- **Frontend**: Flutter (Dart) — Android Mobile App
- **Backend / Database**: Supabase PostgreSQL 15
- **Security**: PostgreSQL Row Level Security (RLS) & `SECURITY DEFINER` Stored Procedures
- **Push Engine**: Firebase Cloud Messaging (FCM HTTP v1) + Supabase Deno Edge Function (`send-push`)
- **State & Stream Management**: Provider + Supabase Realtime Channel

---

## 🗄️ Urutan Migrasi Database Supabase

Seluruh migrasi SQL terletak di folder `supabase/migrations/` dan harus dieksekusi secara berurutan:

1. `001_initial_schema.sql`: Skema dasar tabel `profiles`, `year_counters`, `agenda_numbers`, `activity_logs`.
2. `002_fix_rls_and_admin_view.sql`: Perbaikan RLS & view khusus admin.
3. `003_audit_trail_and_indices.sql`: Indeks performa & pencatatan jejak audit.
4. `004_fix_profile_recursion.sql`: Optimasi query pengecekan profil.
5. `005_fix_rls_infinite_recursion.sql`: Pencegahan rekursi tak hingga pada RLS policy.
6. `006_rpc_issue_number.sql`: Stored Procedure transaksi pembuatan nomor agenda.
7. `007_fix_search_path.sql`: Keamanan `search_path` pada fungsi database.
8. `008_operator_role_and_acc.sql`: Field status ACC (`menunggu`, `disetujui`, `ditolak`) dan peran operator.
9. `009_fix_backdate_rpc.sql`: Prosedur alokasi nomor backdate dari buffer.
10. `010_module4_notifications_and_buffers.sql`: Tabel `buffer_settings`, `agenda_buffers`, `notifications`, fungsi `update_fcm_token`, `approve_agenda`, `reject_agenda`.
11. `011_webhook_send_push.sql`: Trigger database otomatis saat `notifications` di-INSERT untuk memanggil Edge Function `send-push`.
12. `012_test_verification_module4.sql`: Suite pengujian otomatis database untuk seluruh skenario Module 4.
13. `013_notifications_isi_push_and_final_texts.sql`: Penambahan kolom `isi_push` & teks standar final notifikasi.
14. `014_update_agenda_draft_rpc.sql`: Stored procedure `update_agenda_draft` untuk edit draft nomor agenda sebelum di-ACC dengan penguncian nomor & tanggal permanen.

---

## 🚀 Panduan Setup & Menjalankan Proyek

### 1. Prasyarat
- Flutter SDK (versi >= 3.22.0) & Dart SDK
- Android Studio / Android SDK (API 34+)
- Akun Firebase (Firebase Console) & Proyek Supabase

### 2. Konfigurasi Backend (Supabase)
1. Buat project baru di [Supabase Dashboard](https://supabase.com).
2. Jalankan migrasi `001` hingga `013` di SQL Editor Supabase.
3. Deploy Edge Function `send-push`:
   ```bash
   supabase functions deploy send-push --no-verify-jwt
   ```
4. Set secret Firebase Service Account di Supabase:
   ```bash
   supabase secrets set FCM_SERVICE_ACCOUNT='{"type":"service_account","project_id":"...","private_key":"...","client_email":"..."}'
   ```

### 3. Konfigurasi Aplikasi Mobile (Flutter)
1. Salin file `google-services.json` dari Firebase Console ke:
   ```
   flutter_app/android/app/google-services.json
   ```
2. Pastikan konfigurasi URL dan Anon Key Supabase di `flutter_app/lib/main.dart` telah sesuai dengan proyek Anda.
3. Install dependensi Flutter:
   ```bash
   cd flutter_app
   flutter pub get
   ```

---

## 📦 Build Release APK

Untuk menghasilkan file APK rilis Android yang siap diinstal di perangkat:

```bash
cd flutter_app
flutter build apk --release
```

Hasil file APK akan berada di:
`flutter_app/build/app/outputs/flutter-apk/app-release.apk`

---

## ⚠️ Troubleshooting & Tips Notifikasi Android

Pada perangkat Android dengan kustomisasi pabrikan (Xiaomi/MIUI, Oppo/ColorOS, Vivo/FuntouchOS, Samsung/OneUI):

1. **Izin Notifikasi (Android 13+)**:
   - Pastikan aplikasi meminta dan menerima izin **POST_NOTIFICATIONS** saat pertama kali dibuka.
2. **Hemat Baterai (Battery Saver)**:
   - Atur pengaturan baterai aplikasi MONA ke **"Tidak Ada Pembatasan" (No Restrictions)** agar notifikasi tetap masuk saat aplikasi di latar belakang (*background/terminated*).
3. **Mulai Otomatis (Autostart)**:
   - Izinkan **Autostart / Mulai Otomatis** pada menu Pengaturan Aplikasi di ponsel.
4. **Koneksi Jaringan**:
   - Pastikan Google Play Services aktif dan terhubung ke internet.

---

## 👥 Hak Cipta & Pengembang

Dikembangkan untuk **Dinas Komunikasi dan Informatika (Diskominfo) Pemerintah Kota Malang**.
Hak Cipta © 2026 MONA Team. Seluruh hak cipta dilindungi undang-undang.
