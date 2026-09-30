# PRD — MONA (Monitoring Nomor Agenda)
Diskominfo | v1.0

## 1. Ringkasan
MONA adalah aplikasi penomoran agenda surat (Surat Keputusan, Nota Dinas, Surat
Keluar) yang bisa diakses realtime oleh staf Diskominfo, baik dari kantor maupun dari
luar kantor (mobile). Aplikasi menggantikan pencatatan manual nomor agenda dengan sistem
yang otomatis, berurutan, anti-tabrakan nomor, dan punya alur approval.

## 2. Latar Belakang / Masalah
- Penomoran agenda surat saat ini dilakukan manual, rawan nomor ganda/tidak berurutan
  terutama saat beberapa staf menginput bersamaan.
- Staf perlu tetap bisa membuat/memantau nomor agenda meski sedang tidak di kantor.
- Perlu ada kontrol (approval oleh admin) sebelum nomor dianggap final/sah.

## 3. Tujuan
1. Operator dapat membuat nomor agenda secara realtime, kapan saja, dari mana saja.
2. Nomor agenda terjamin unik dan berurutan (tidak ada duplikasi walau diakses bersamaan).
3. Admin dapat memverifikasi (ACC) setiap nomor yang dibuat sebelum final.
4. Tersedia mekanisme pengambilan nomor untuk tanggal mundur (backdate) tanpa merusak urutan.

## 4. Target Pengguna & Role
| Role | Deskripsi | Hak Akses Utama |
|---|---|---|
| **Operator** | Staf yang menginput permintaan nomor agenda | Login, buat nomor agenda (hari ini/backdate), edit data sebelum ACC, lihat Home (semua nomor, semua operator) |
| **Admin** | Staf yang memverifikasi nomor agenda | Login, lihat semua pengajuan, ACC/tolak, lihat Home |

## 5. Ruang Lingkup

### In Scope (v1)
- Login & manajemen sesi (role admin/operator), auto tetap login sampai logout manual
- Form input nomor agenda: kategori, kode klasifikasi, tujuan surat, perihal, pemohon
- Pilihan "hari ini" (generate langsung) atau "tanggal sebelumnya" (ambil dari stok buffer)
- Generate nomor agenda otomatis, format: `kode_klasifikasi / nomor_agenda / template_tetap / tahun`
- **Nomor agenda terpisah per kategori** (Surat Keputusan, Nota Dinas, Surat Keluar
  masing-masing punya urutan nomor sendiri, mulai dari 1)
- Buffer nomor cadangan otomatis (default 5, bisa diatur admin per kategori — lihat 7.3)
  untuk kebutuhan backdate
- Notifikasi "nomor agenda tanggal/bulan ini sudah habis" jika stok buffer habis
- Admin ACC (approve) nomor agenda — begitu di-ACC, data terkunci total
- Operator dapat edit kategori/kode klasifikasi/tujuan surat/perihal/pemohon selama
  **belum** ACC (nomor agenda & tanggal tidak pernah bisa diedit, sejak awal dibuat)
- Halaman Home (list nomor agenda, dikelompokkan per bulan → per tanggal, nomor lengkap
  ditampilkan tebal), terlihat oleh semua operator & admin (bukan hanya milik sendiri)
- Reset otomatis nomor agenda ke 1 setiap pergantian tahun (per kategori)
- **Notifikasi** (push + in-app) untuk 2 event: operator diberitahu saat nomornya
  di-ACC/ditolak, dan admin diberitahu saat ada pengajuan nomor baru — lihat 7.8

### Out of Scope (v1 — kandidat pengembangan lanjutan)
- Cetak/generate dokumen surat resmi (PDF/Word) — v1 hanya mencatat nomor
- Notifikasi untuk stok buffer menipis/habis (baru 2 event di 7.8 yang masuk v1)
- Multi-instansi / multi-tenant
- Riwayat perubahan (audit trail) detail per field
- Approval berjenjang (lebih dari 1 level admin)

## 6. User Stories per Modul
(Selaras dengan rencana pengerjaan mingguan)

### Modul 1 — Persiapan Proyek & Autentikasi
- Sebagai operator, saya ingin login agar dapat mengakses aplikasi.
- Sebagai admin, saya ingin login agar dapat mengelola pengajuan nomor.
- Sebagai pengguna, saya ingin tetap login sampai logout.

### Modul 2 — Pembuatan Nomor Agenda
- Sebagai operator, saya ingin membuat nomor agenda.
- Sebagai operator, saya ingin memilih hari ini atau hari sebelumnya.
- Sebagai operator, saya ingin melihat hasil nomor agenda.

### Modul 3 — Manajemen Nomor & Approval
- Sebagai admin, saya ingin melihat semua pengajuan.
- Sebagai admin, saya ingin meng-ACC nomor agenda.
- Sebagai operator, saya ingin mengedit data sebelum ACC.
- Sebagai operator/admin, saya ingin melihat Home berisi semua nomor agenda yang sudah
  dibuat, dikelompokkan per bulan lalu per tanggal.

### Modul 4 — Otomatisasi, Penyempurnaan & Testing
- Sebagai operator, saya ingin nomor cadangan tersedia otomatis.
- Sebagai admin, saya ingin mengatur jumlah nomor cadangan per kategori.
- Sebagai operator, saya ingin diberi tahu (notifikasi) saat nomor agenda saya
  disetujui atau ditolak admin.
- Sebagai admin, saya ingin diberi tahu (notifikasi) saat ada pengajuan nomor baru
  dari operator.
- Sebagai admin, saya ingin sistem stabil digunakan banyak pengguna bersamaan.

## 7. Functional Requirements (Detail)

### 7.1 Format Nomor
`[kode_klasifikasi] / [nomor_agenda] / [template_tetap]/[tahun]`
Contoh: `500.12.8.2 / 1036 / 35.07.315/2026`
- `kode_klasifikasi`: input manual bebas oleh operator, bisa beda-beda tiap surat.
- `nomor_agenda`: dihasilkan sistem. **Setiap kategori (Surat Keputusan, Nota Dinas,
  Surat Keluar) punya urutan nomornya sendiri-sendiri**, tidak berbagi urutan dengan
  kategori lain (mis. Surat Keluar bisa di angka 1036 sementara Nota Dinas baru di
  angka 42, keduanya berjalan independen).
- `template_tetap` + `tahun`: tetap sama untuk semua surat dalam tahun berjalan
  (template dikonfigurasi di sistem, tahun otomatis mengikuti tahun berjalan).

### 7.2 Alur Pembuatan Nomor
1. Operator isi: kategori (Surat Keputusan / Nota Dinas / Surat Keluar), kode klasifikasi,
   tujuan surat, perihal, pemohon.
2. Klik "Buat Nomor Agenda" → muncul pilihan: **Hari ini** atau **Tanggal sebelumnya**.
3. **Hari ini**: sistem langsung generate nomor urut berikutnya secara realtime (WIB),
   mengikuti urutan nomor **kategori yang dipilih saja**.
4. **Tanggal sebelumnya**: operator tetap pilih tanggal spesifik lewat kalender (untuk
   semua kategori, termasuk yang buffernya bulanan — lihat 7.3) → sistem ambil 1 nomor
   dari stok buffer milik kategori & periode tersebut. Jika stok sudah habis →
   tampilkan pesan "Nomor Agenda Untuk Tanggal Tersebut Sudah Habis, silahkan koordinasi
   lebih lanjut dengan TU" (operator kembali manual, tidak ada auto-redirect tanggal lain).
5. Nomor langsung tersimpan/keluar (bukan status "pending" yang menahan nomor) dan otomatis
   masuk antrian ACC admin dengan status **Menunggu**.

### 7.3 Buffer Nomor Cadangan (per Kategori)
Buffer sekarang **berbeda periodenya per kategori**, dan **jumlahnya bisa diatur admin**:

| Kategori | Frekuensi generate buffer | Jumlah default |
|---|---|---|
| Surat Keluar | Harian (tiap 00:00 WIB) | 5 |
| Nota Dinas | Bulanan (tiap awal bulan, 00:00 WIB) | 5 |
| Surat Keputusan | Bulanan (tiap awal bulan, 00:00 WIB) | 5 |

- **Frekuensinya tetap** (tidak bisa diubah admin) — Surat Keluar selalu harian, dua
  kategori lain selalu bulanan. Ini bawaan sistem berdasarkan kategori.
- **Jumlah buffer bisa diatur admin** per kategori (mis. ubah dari 5 jadi 8 khusus Surat
  Keluar). Kalau admin tidak mengubah apa pun, otomatis pakai nilai default di atas (5).
- Untuk kategori harian (Surat Keluar): setiap 00:00 WIB, sistem generate N nomor
  cadangan (N = setting admin, default 5) setelah nomor terakhir yang dipakai hari itu,
  dialokasikan khusus untuk tanggal tersebut.
- Untuk kategori bulanan (Nota Dinas, Surat Keputusan): setiap awal bulan (00:00 WIB
  tanggal 1), sistem generate N nomor cadangan (default 5) untuk **bulan yang baru saja
  berakhir**, tidak per tanggal harian.
- Operator tetap memilih **tanggal spesifik** lewat kalender saat backdate untuk semua
  kategori (termasuk kategori bulanan) — untuk kategori bulanan, sistem otomatis
  mencocokkan ke stok bulan dari tanggal yang dipilih, bukan ke tanggal persis.
- Reset ke nomor 1 setiap pergantian tahun (1 Januari), berlaku independen per kategori.

### 7.3.1 Pengaturan Buffer oleh Admin
- Admin dapat mengubah **jumlah** buffer per kategori lewat halaman pengaturan.
- Frekuensi (harian/bulanan) tidak muncul sebagai opsi yang bisa diubah — hanya
  ditampilkan sebagai informasi (read-only) di halaman pengaturan yang sama.

### 7.4 Approval (ACC)
- Admin melihat daftar semua nomor berstatus "Menunggu".
- Admin dapat **menyetujui** (status → Disetujui, data terkunci total, tidak bisa diedit
  siapa pun lagi) atau **menolak** (status → Ditolak, dengan catatan opsional).
- Nomor yang sudah dikeluarkan tetap tercatat (tidak dihapus) meskipun ditolak, untuk
  menjaga urutan nomor tidak bolong secara tidak wajar.

### 7.5 Edit Data
- Selama status **Menunggu**: operator (siapa pun, bukan hanya pembuat) dapat mengedit
  kategori, kode klasifikasi, tujuan surat, perihal, pemohon.
- Nomor agenda & tanggal **tidak pernah bisa diedit** sejak awal dibuat.
- Setelah status **Disetujui**: seluruh data terkunci, tidak ada yang bisa mengedit.

### 7.6 Halaman Home
- Menampilkan seluruh nomor agenda yang sudah dibuat (bukan hanya milik operator yang
  login), dikelompokkan **per bulan → per tanggal** agar tidak perlu scroll panjang
  sepanjang tahun.
- Format tampilan per item (**nomor lengkap ditampilkan tebal/bold**):
  ```
  Kategori: Surat Keluar
  **500.12.8.2/1036/35.07.315/2026**
  Perihal: ...
  Tujuan Surat: ...
  User bidang: ... (pemohon)
  ```
- Terlihat oleh operator maupun admin.

### 7.7 Halaman Home — Khusus Admin (2 Tab)
Berdasarkan prototype: Home admin terbagi menjadi **2 tab/halaman terpisah**, bukan satu
list tercampur:
- **Tab "Menunggu" (Pending)** — daftar nomor agenda berstatus `menunggu`, siap di-ACC.
- **Tab "Disetujui" (ACC)** — daftar nomor agenda berstatus `disetujui`.
- Begitu admin meng-ACC sebuah nomor di tab Pending, item tersebut **hilang dari tab
  Pending dan otomatis muncul di tab Disetujui** (real-time, tanpa perlu refresh manual
  idealnya, minimal langsung ter-update begitu admin kembali ke tab tsb).
- Kedua tab tetap mengikuti pengelompokan per bulan → per tanggal seperti 7.6.
- Nomor yang **ditolak** (status `ditolak`) — untuk v1, cukup tampil di tab Pending dengan
  penanda "Ditolak" (tidak perlu tab ke-3 terpisah), kecuali nanti diputuskan lain.

### 7.8 Notifikasi
Dua jenis notifikasi berjalan bersamaan untuk tiap event: **push notification** (muncul
di HP walau aplikasi tertutup) dan **in-app notification** (lonceng/badge di dalam app,
berisi riwayat notifikasi yang bisa dibuka kapan saja).

| Event | Penerima | Isi Notifikasi |
|---|---|---|
| Nomor agenda **disetujui** admin | Operator pembuat nomor tsb | "Nomor agenda Anda **{nomor_lengkap}** telah **disetujui**." |
| Nomor agenda **ditolak** admin | Operator pembuat nomor tsb | "Nomor agenda Anda **{nomor_lengkap}** **ditolak**." + catatan admin (jika ada) |
| Ada **pengajuan baru** dari operator | Semua akun admin | "Pengajuan baru dari **{nama_operator}**: {kategori} — {nomor_lengkap}" |

- Notifikasi stok buffer menipis/habis **tidak** termasuk v1 (lihat Out of Scope) —
  bisa ditambah belakangan tanpa perombakan besar karena infrastrukturnya sudah ada.
- Menyentuh/tap notifikasi (baik push maupun in-app) idealnya membawa pengguna langsung
  ke detail surat terkait di Home.
- In-app notification punya status terbaca/belum terbaca, ditampilkan sebagai badge
  jumlah notifikasi belum dibaca di ikon lonceng.

## 8. Non-Functional Requirements


- **Realtime & Timezone**: seluruh logic waktu (generate hari ini, cutoff 00:00, reset
  tahunan) mengikuti WIB (Asia/Jakarta), bukan waktu server default.
- **Konsistensi Data**: tidak boleh ada nomor agenda ganda meskipun beberapa operator
  mengakses/generate nomor secara bersamaan (butuh locking/transaction di level database).
- **Ketersediaan**: aplikasi bisa diakses dari mobile (prioritas utama) dan web.
- **Keamanan**: autentikasi berbasis JWT, password di-hash, akses endpoint dibatasi
  berdasarkan role.
- **Auditability minimal**: setiap nomor mencatat siapa pembuat dan siapa yang meng-ACC.

## 9. Asumsi & Batasan
- Skala pengguna kecil-menengah (puluhan operator, beberapa admin per instansi).
- Belum ada server sendiri — akan pakai VPS/cloud data center lokal Indonesia (perlu
  konfirmasi kebijakan internal terkait PDN/PSE sebelum pilih vendor final).
- Template tetap & format nomor mengikuti kebijakan internal Diskominfo, bisa dikonfigurasi
  admin bila sewaktu-waktu berubah.
- Push notification butuh **Firebase project terpisah** (Firebase Cloud Messaging) di
  luar Supabase — perlu dibuatkan akun/project Firebase khusus untuk MONA, ini
  komponen infrastruktur tambahan di luar Supabase.

## 10. Kriteria Sukses
- Operator dapat membuat nomor agenda dari HP di luar kantor tanpa error.
- Tidak ditemukan nomor ganda/tidak berurutan dalam pengujian akses bersamaan.
- Admin dapat menyetujui/menolak nomor dan data langsung terkunci sesuai aturan.
- Buffer cadangan & reset tahunan berjalan otomatis tanpa intervensi manual.

## 11. Timeline
Dikerjakan dalam 4 tahap mingguan (27 Juli – 23 Agustus 2026):
1. Persiapan Proyek & Autentikasi
2. Pembuatan Nomor Agenda
3. Manajemen Nomor & Approval
4. Otomatisasi, Penyempurnaan & Testing
