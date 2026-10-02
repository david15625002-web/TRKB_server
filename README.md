<div align="center">

# TRKB · Sistem Informasi Mahasiswa

**Teknik Robotika & Kecerdasan Buatan — Universitas Komputer Indonesia**

Jadwal · Tugas · Struktur Organisasi · Profil · Obrolan

`PWA` · `Next.js` · `Supabase` · `PostgreSQL` · `Web Push`

</div>

---

> **Status: `PHASE 0 — DESIGN`**
> Repositori ini saat ini berisi **perencanaan dan desain**, bukan aplikasi produksi.
> Belum ada kode aplikasi. Lihat [`docs/10-roadmap.md`](docs/10-roadmap.md) untuk urutan pengerjaan.

## Apa ini?

Satu tempat untuk semua hal administratif kelas di program studi Teknik Robotika &
Kecerdasan Buatan, supaya informasi tidak lagi hilang di tengah grup WhatsApp:

| # | Kemampuan | Ringkas |
|---|-----------|---------|
| 1 | **Jadwal** | Jadwal kuliah per kelas per semester. Diinput sekali oleh sekretaris (manual atau impor CSV/Excel), lalu seluruh pertemuan mingguan dibuat otomatis. Perubahan ruang, kuliah pengganti, dan pembatalan ditangani per-pertemuan. |
| 2 | **Peran & Struktur** | Hirarki berjangkauan: Ketua HIMA → Divisi → Kelas → Anggota. Ketua Kelas `TRKB-1 25` secara teknis **tidak bisa** mengubah data kelas lain. Struktur HIMA bisa ditambah/dihapus Super Admin. |
| 3 | **Tugas & Pengingat** | Ketua Kelas / Sekretaris memasukkan tugas dari dosen. Sistem mengirim pengingat **H-1** (plus H-3 jam) ke setiap anggota kelas lewat notifikasi dalam aplikasi, push, dan email. |
| 4 | **Profil** | Avatar, banner, bio, tema pilihan sendiri, tag keahlian robotika, portofolio proyek, dan lencana pencapaian. |
| 5 | **Obrolan** | Ruang otomatis per kelas & per divisi, kanal pengumuman, ruang publik, dan pesan pribadi (DM). Realtime. |

## Prinsip desain

1. **Data masuk sekali.** Sekretaris menginput jadwal satu kali per semester; sistem yang menurunkan semua pertemuan, pengingat, dan tampilan.
2. **Peran dijaga database, bukan UI.** Semua izin ditegakkan oleh Row Level Security di PostgreSQL. Menyembunyikan tombol bukan keamanan.
3. **Semester berjalan sendiri.** Kelas disimpan sebagai *angkatan*, bukan *semester*. `TRKB-1 25` otomatis naik semester tanpa migrasi manual.
4. **Jujur soal privasi.** DM tidak terenkripsi ujung-ke-ujung pada v1, dan aplikasi menyatakannya terang-terangan. Tidak ada janji privasi palsu.
5. **Milik program studi, bukan milik satu orang.** Pergantian kepengurusan = mengubah tanggal jabatan, bukan menyerahkan password.

## Dokumentasi

| Dokumen | Isi |
|---------|-----|
| [`01-vision-and-scope.md`](docs/01-vision-and-scope.md) | Masalah, pengguna, batasan v1, yang **tidak** dibangun |
| [`02-architecture.md`](docs/02-architecture.md) | Diagram sistem, pilihan teknologi + alasannya, struktur folder |
| [`03-data-model.md`](docs/03-data-model.md) | Entitas, relasi, keputusan pemodelan |
| [`04-roles-and-permissions.md`](docs/04-roles-and-permissions.md) | Matriks peran × izin, strategi RLS |
| [`05-notifications.md`](docs/05-notifications.md) | Mesin pengingat, penjadwalan, anti-spam, jam tenang |
| [`06-chat.md`](docs/06-chat.md) | Model ruang, realtime, moderasi |
| [`07-profiles-and-gamification.md`](docs/07-profiles-and-gamification.md) | Profil, keahlian, portofolio, lencana |
| [`08-design-system.md`](docs/08-design-system.md) | Token tema, 4 preset, tipografi, animasi |
| [`09-api-contract.md`](docs/09-api-contract.md) | Endpoint, bentuk payload, aturan validasi |
| [`10-roadmap.md`](docs/10-roadmap.md) | Fase pengerjaan + estimasi |
| [`11-open-questions.md`](docs/11-open-questions.md) | Keputusan yang masih perlu jawaban |

## Basis data

| Berkas | Isi |
|--------|-----|
| [`db/schema.sql`](db/schema.sql) | Seluruh DDL: tipe, tabel, indeks, trigger, fungsi |
| [`db/policies.sql`](db/policies.sql) | Fungsi izin + kebijakan Row Level Security |
| [`db/seed.sql`](db/seed.sql) | Data contoh TRKB untuk pengembangan |

## Pratinjau antarmuka

Prototipe HTML yang bisa diklik — tanpa build, tanpa dependensi:

```bash
# buka langsung
xdg-open mockup/index.html

# atau layani lewat http
python3 -m http.server 8080 --directory mockup
```

Prototipe memuat 10 layar, 4 preset tema (Cyan HUD, Amber Industrial, Campus,
Blueprint) masing-masing dengan mode terang & gelap, dan animasi yang
direncanakan untuk aplikasi sebenarnya. Lihat [`mockup/README.md`](mockup/README.md).

## Lisensi

Belum ditentukan — lihat [`docs/11-open-questions.md`](docs/11-open-questions.md).

---

<details>
<summary><strong>English summary</strong></summary>

A student-information PWA for the Robotics & AI Engineering program at UNIKOM.
Five capabilities: per-class semester schedules, a scoped role hierarchy
(Ketua HIMA → Division → Class), lecturer-task tracking with H-1 reminders,
customisable profiles with a robotics portfolio, and realtime chat rooms + DMs.

This repository is currently **design-phase only**: specifications, a complete
PostgreSQL schema with Row Level Security policies, and a clickable HTML
prototype. No application code yet — start at [`docs/10-roadmap.md`](docs/10-roadmap.md).

</details>
