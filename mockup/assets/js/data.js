/* ==========================================================================
   TRKB prototype · sample data
   Mirrors db/seed.sql so the mockup shows the same shapes the schema defines.
   Class code format: 'TRKB-1 25' = TRKB, kelas 1, angkatan 2025.
   ========================================================================== */

const DATA = {
  me: {
    nama: 'Namamu',
    display: 'Namamu',
    nim: '15625001',
    kelas: 'TRKB-1 25',
    semester: 3,
    peran: 'Ketua Kelas',
    pronouns: '—',
    headline: 'Suka bikin line follower dan belajar ROS 2',
    bio: 'Mahasiswa Teknik Robotika dan Kecerdasan Buatan, UNIKOM. Fokus di kendali dan sistem tertanam.',
    inisial: 'N',
    stats: { selesai: 42, tepat: 38, telat: 4, streak: 12, streakBest: 19 },
  },

  term: { nama: 'Semester Ganjil 2026/2027', kode: '2026/2027-1', pekan: 4, totalPekan: 16 },

  hari: ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat'],

  // Jadwal for TRKB-1 25, semester 3
  jadwal: [
    { hari: 0, mulai: '07:00', selesai: '09:30', mk: 'Sistem Kendali',        kode: 'TRKB-301', dosen: 'Dr. Dosen Pengampu Satu, S.T., M.T.', ruang: 'Lab Robotika 2', jenis: 'praktikum', status: 'scheduled' },
    { hari: 0, mulai: '10:00', selesai: '12:30', mk: 'Kecerdasan Artifisial', kode: 'TRKB-302', dosen: 'Dosen Pengampu Dua, S.T., M.Kom.',     ruang: 'R.301',          jenis: 'teori',     status: 'scheduled' },
    { hari: 1, mulai: '08:00', selesai: '10:30', mk: 'Sensor dan Aktuator',   kode: 'TRKB-303', dosen: 'Ir. Dosen Pengampu Tiga, M.T.',       ruang: 'Lab Elektronika', jenis: 'praktikum', status: 'scheduled' },
    { hari: 1, mulai: '13:00', selesai: '14:40', mk: 'Metodologi Penelitian', kode: 'TRKB-405', dosen: 'Dr. Dosen Pengampu Lima, M.Eng.',     ruang: 'R.205',          jenis: 'teori',     status: 'cancelled', catatan: 'Dosen tugas ke luar kota' },
    { hari: 2, mulai: '07:00', selesai: '09:30', mk: 'Mikrokontroler',        kode: 'TRKB-203', dosen: 'Ir. Dosen Pengampu Tiga, M.T.',       ruang: 'Lab Robotika 1', jenis: 'praktikum', status: 'scheduled' },
    { hari: 2, mulai: '10:00', selesai: '11:40', mk: 'Struktur Data',         kode: 'TRKB-202', dosen: 'Dosen Pengampu Empat, S.Kom., M.T.',  ruang: 'Lab Komputer 3', jenis: 'teori',     status: 'scheduled' },
    { hari: 3, mulai: '09:00', selesai: '11:30', mk: 'Elektronika Digital',   kode: 'TRKB-201', dosen: 'Dosen Pengampu Dua, S.T., M.Kom.',    ruang: 'Lab Elektronika', jenis: 'praktikum', status: 'moved', catatan: 'Pindah dari Rabu 13:00' },
    { hari: 4, mulai: '07:30', selesai: '09:10', mk: 'Matematika Teknik II',  kode: 'TRKB-204', dosen: 'Dr. Dosen Pengampu Satu, S.T., M.T.', ruang: 'R.402',          jenis: 'teori',     status: 'scheduled' },
    { hari: 4, mulai: '10:00', selesai: '12:30', mk: 'Menggambar Teknik dan CAD', kode: 'TRKB-205', dosen: 'Dosen Pengampu Empat, S.Kom., M.T.', ruang: 'Studio CAD', jenis: 'praktikum', status: 'scheduled' },
  ],

  // jam offsets used by the week grid
  jamGrid: ['07:00', '08:00', '09:00', '10:00', '11:00', '12:00', '13:00', '14:00'],

  tugas: [
    { id: 't1', judul: 'Laporan Praktikum Mikrokontroler Pekan 4', mk: 'Mikrokontroler', kode: 'TRKB-203',
      dosen: 'Ir. Dosen Pengampu Tiga, M.T.', jenis: 'praktikum', prioritas: 'urgent',
      jamLagi: 5, kanal: 'Kumpulkan di kelas', state: 'todo',
      ket: 'Sertakan skematik, kode program, dan dokumentasi pengujian sensor ultrasonik.' },
    { id: 't2', judul: 'Tugas Besar: Kendali PID Motor DC', mk: 'Sistem Kendali', kode: 'TRKB-301',
      dosen: 'Dr. Dosen Pengampu Satu, S.T., M.T.', jenis: 'proyek', prioritas: 'high',
      jamLagi: 30, kanal: 'LMS UNIKOM', state: 'in_progress',
      ket: 'Kelompok 3 orang. Tuning PID, grafik respons step, dan analisis overshoot.' },
    { id: 't3', judul: 'Quiz 2 — Pencarian Heuristik', mk: 'Kecerdasan Artifisial', kode: 'TRKB-302',
      dosen: 'Dosen Pengampu Dua, S.T., M.Kom.', jenis: 'quiz', prioritas: 'normal',
      jamLagi: 78, kanal: 'Di kelas', state: 'todo', ket: 'Materi A*, greedy best-first, dan hill climbing.' },
    { id: 't4', judul: 'Ringkasan Jurnal SLAM', mk: 'Metodologi Penelitian', kode: 'TRKB-405',
      dosen: 'Dr. Dosen Pengampu Lima, M.Eng.', jenis: 'tugas', prioritas: 'normal',
      jamLagi: 150, kanal: 'Email dosen', state: 'todo', ket: 'Minimal 3 jurnal terindeks, format IEEE.' },
    { id: 't5', judul: 'Gambar Teknik Gripper 2 Jari', mk: 'Menggambar Teknik dan CAD', kode: 'TRKB-205',
      dosen: 'Dosen Pengampu Empat, S.Kom., M.T.', jenis: 'tugas', prioritas: 'low',
      jamLagi: -20, kanal: 'LMS UNIKOM', state: 'done', ket: 'Tampak depan, samping, dan isometrik.' },
  ],

  organisasi: {
    nama: 'HIMA Teknik Robotika dan Kecerdasan Buatan',
    bph: [
      { nama: 'Ketua Himpunan',        orang: 'A. Pratama',  nim: '15624001', inisial: 'AP' },
      { nama: 'Wakil Ketua Himpunan',  orang: 'B. Nugraha',  nim: '15624014', inisial: 'BN' },
      { nama: 'Sekretaris Himpunan',   orang: 'C. Lestari',  nim: '15624022', inisial: 'CL' },
      { nama: 'Bendahara Himpunan',    orang: 'D. Saputra',  nim: '15624031', inisial: 'DS' },
    ],
    divisi: [
      { nama: 'Divisi Riset dan Teknologi',  kadiv: 'E. Ramadhan', anggota: 9, inisial: 'ER' },
      { nama: 'Divisi Hubungan Masyarakat',  kadiv: 'F. Aulia',    anggota: 6, inisial: 'FA' },
      { nama: 'Divisi Acara',                kadiv: 'G. Hakim',    anggota: 8, inisial: 'GH' },
      { nama: 'Divisi Media dan Informasi',  kadiv: 'H. Safira',   anggota: 7, inisial: 'HS' },
      { nama: 'Divisi Kaderisasi',           kadiv: 'I. Wijaya',   anggota: 5, inisial: 'IW' },
    ],
    kelas: [
      { kode: 'TRKB-1 25', semester: 3, anggota: 38, ketua: 'Namamu',     sekretaris: 'J. Anindya', pending: 2 },
      { kode: 'TRKB-2 25', semester: 3, anggota: 36, ketua: 'K. Hartono', sekretaris: 'L. Maheswari', pending: 0 },
      { kode: 'TRKB-1 24', semester: 5, anggota: 34, ketua: 'M. Fadhil',  sekretaris: 'N. Qureshi', pending: 1 },
      { kode: 'TRKB-2 24', semester: 5, anggota: 31, ketua: 'O. Pangestu', sekretaris: 'P. Rahmadani', pending: 0 },
      { kode: 'TRKB-1 23', semester: 7, anggota: 29, ketua: 'Q. Siregar', sekretaris: 'R. Utami', pending: 0 },
    ],
  },

  menunggu: [
    { nama: 'S. Hidayat', nim: '15625044', kelas: 'TRKB-1 25', kapan: '2 jam lalu', inisial: 'SH' },
    { nama: 'T. Kurniawan', nim: '15625045', kelas: 'TRKB-1 25', kapan: '5 jam lalu', inisial: 'TK' },
  ],

  ruang: [
    { id: 'r1', nama: 'TRKB-1 25', jenis: 'class', terakhir: 'J. Anindya: jadwal Eldig pindah ke Kamis ya', belum: 3, ikon: '◉' },
    { id: 'r2', nama: 'Pengumuman TRKB', jenis: 'announcement', terakhir: 'Sekretaris HIMA: Rapat pleno Sabtu 09:00', belum: 1, ikon: '◈' },
    { id: 'r3', nama: 'Divisi Riset dan Teknologi', jenis: 'division', terakhir: 'E. Ramadhan: komponen KRI sudah datang', belum: 0, ikon: '◆' },
    { id: 'r4', nama: 'Ngobrol Bebas', jenis: 'public', terakhir: 'U. Pradana: ada yang punya jumper male-male?', belum: 0, ikon: '○' },
    { id: 'r5', nama: 'J. Anindya', jenis: 'dm', terakhir: 'Oke, nanti aku input tugasnya', belum: 0, ikon: '◐' },
  ],

  pesan: {
    r1: [
      { sys: true, isi: 'Ruang ini dibuat otomatis untuk kelas TRKB-1 25' },
      { nama: 'J. Anindya', peran: 'Sekretaris Kelas', inisial: 'JA', jam: '08:12', isi: 'Pagi semua. Jadwal Elektronika Digital pindah ke Kamis 09:00 di Lab Elektronika ya.' },
      { nama: 'V. Alamsyah', peran: 'Anggota', inisial: 'VA', jam: '08:14', isi: 'Noted. Yang Rabu jadi kosong berarti?' },
      { nama: 'J. Anindya', peran: 'Sekretaris Kelas', inisial: 'JA', jam: '08:15', isi: 'Iya, Rabu 13:00 kosong. Sudah aku update di jadwal, jadi notifikasinya ikut berubah.' },
      { me: true, nama: 'Namamu', peran: 'Ketua Kelas', inisial: 'N', jam: '08:20', isi: 'Makasih. Aku umumkan juga di kanal pengumuman.' },
      { nama: 'W. Oktaviani', peran: 'Anggota', inisial: 'WO', jam: '08:31', isi: 'Laporan praktikum mikro dikumpul besok kan? Dapat notif H-1 tadi malam.' },
      { me: true, nama: 'Namamu', peran: 'Ketua Kelas', inisial: 'N', jam: '08:33', isi: 'Betul, besok 23:59. Jangan lupa skematiknya dilampirkan.' },
    ],
    r2: [
      { sys: true, isi: 'Kanal pengumuman — hanya pengurus dapat mengirim' },
      { nama: 'C. Lestari', peran: 'Sekretaris HIMA', inisial: 'CL', jam: 'Sen 10:02', isi: 'Rapat pleno kepengurusan hari Sabtu 09:00 di R.401. Wajib untuk seluruh BPH dan kadiv.' },
    ],
    r3: [
      { nama: 'E. Ramadhan', peran: 'Kadiv Ristek', inisial: 'ER', jam: '19:40', isi: 'Komponen untuk KRI sudah datang. Besok mulai assembly di Lab Robotika 1.' },
      { me: true, nama: 'Namamu', peran: 'Anggota Divisi', inisial: 'N', jam: '19:52', isi: 'Siap, aku bawa solder station sendiri.' },
    ],
    r4: [
      { nama: 'U. Pradana', peran: 'Anggota', inisial: 'UP', jam: '14:20', isi: 'Ada yang punya jumper male-male lebih? Punyaku kurang 10.' },
    ],
    r5: [
      { nama: 'J. Anindya', peran: 'Sekretaris Kelas', inisial: 'JA', jam: '07:58', isi: 'Tugas dari Pak Tiga tadi aku input ya?' },
      { me: true, nama: 'Namamu', peran: 'Ketua Kelas', inisial: 'N', jam: '08:01', isi: 'Iya tolong. Tenggat besok 23:59, kanal kumpul di kelas.' },
      { nama: 'J. Anindya', peran: 'Sekretaris Kelas', inisial: 'JA', jam: '08:02', isi: 'Oke, nanti aku input tugasnya' },
    ],
  },

  keahlian: [
    { n: 'Arduino', k: 'embedded', lv: 3 }, { n: 'ESP32', k: 'embedded', lv: 2 },
    { n: 'Embedded C/C++', k: 'embedded', lv: 2 }, { n: 'Kendali PID', k: 'ai', lv: 3 },
    { n: 'Python', k: 'software', lv: 3 }, { n: 'ROS 2', k: 'software', lv: 1 },
    { n: 'OpenCV', k: 'ai', lv: 2 }, { n: 'Desain PCB', k: 'electronics', lv: 2 },
    { n: 'Fusion 360', k: 'mechanical', lv: 1 }, { n: 'Git', k: 'tooling', lv: 2 },
  ],

  proyek: [
    { judul: 'Line Follower PID', konteks: 'Tugas Besar Mikrokontroler', tahun: 2026,
      ringkas: 'Robot line follower dengan kendali PID, 8 sensor TCRT5000, dan ESP32.',
      tag: ['Arduino', 'Kendali PID', 'Desain PCB'], tim: 3 },
    { judul: 'Lengan Robot 4-DOF', konteks: 'Lomba internal HIMA 2026', tahun: 2026,
      ringkas: 'Lengan 4 derajat kebebasan dengan kinematika invers, dikendalikan lewat antarmuka web.',
      tag: ['Kinematika Robot', 'Python', 'Fusion 360'], tim: 4 },
    { judul: 'Deteksi Rambu Lalu Lintas', konteks: 'Proyek mandiri', tahun: 2025,
      ringkas: 'YOLOv8 untuk deteksi rambu, dijalankan di Raspberry Pi 4 dengan 14 FPS.',
      tag: ['YOLO / Deteksi Objek', 'OpenCV', 'Python'], tim: 1 },
  ],

  lencana: [
    { ic: '👣', n: 'Langkah Pertama', t: 'bronze', punya: true },
    { ic: '⏱', n: 'Tepat Waktu', t: 'bronze', punya: true },
    { ic: '🔥', n: 'Runtun 7 Hari', t: 'bronze', punya: true },
    { ic: '🔧', n: 'Perakit', t: 'bronze', punya: true },
    { ic: '👑', n: 'Pengurus', t: 'special', punya: true },
    { ic: '✏️', n: 'Juru Catat', t: 'special', punya: true },
    { ic: '🎖', n: 'Disiplin', t: 'silver', punya: false },
    { ic: '🏅', n: 'Runtun 30 Hari', t: 'gold', punya: false },
    { ic: '🛡', n: 'Semester Bersih', t: 'gold', punya: false },
    { ic: '⚙️', n: 'Insinyur', t: 'silver', punya: false },
    { ic: '✨', n: 'Serba Bisa', t: 'silver', punya: false },
  ],

  notifikasi: [
    { ic: '⏰', j: 'Besok: Laporan Praktikum Mikrokontroler', b: 'Mikrokontroler · dikumpulkan 23:59', w: '18:00 kemarin', baru: true },
    { ic: '👤', j: '2 anggota menunggu persetujuan', b: 'S. Hidayat dan T. Kurniawan ingin bergabung ke TRKB-1 25', w: '2 jam lalu', baru: true },
    { ic: '🚫', j: 'Kelas dibatalkan', b: 'Metodologi Penelitian · Dosen tugas ke luar kota', w: '5 jam lalu', baru: true },
    { ic: '📍', j: 'Jadwal kelas berubah', b: 'Elektronika Digital pindah ke Kamis 09:00', w: 'kemarin', baru: false },
    { ic: '🔥', j: 'Runtun 12 hari', b: 'Dua belas hari tanpa tugas terlambat.', w: '2 hari lalu', baru: false },
  ],

  // Accent seeds. Hex here is only the swatch in the picker; the real tokens
  // live in tokens.css, where each seed has tuned light and dark values.
  seeds: [
    { id: 'indigo', nama: 'Indigo', hex: '#5b5bd6' },
    { id: 'blue',   nama: 'Biru',   hex: '#1971e3' },
    { id: 'green',  nama: 'Hijau',  hex: '#1c853a' },
    { id: 'amber',  nama: 'Jingga', hex: '#ba5a08' },
    { id: 'pink',   nama: 'Merah muda', hex: '#ce3a75' },
    { id: 'teal',   nama: 'Tosca',  hex: '#008476' },
  ],
};
