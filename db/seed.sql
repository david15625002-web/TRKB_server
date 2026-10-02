-- ============================================================================
--  TRKB · Seed data
--  Apply AFTER schema.sql and policies.sql.
--
--  Contains: the role catalogue, the program + HIMA structure, academic terms,
--  classes in the real campus format, subjects, lecturers, skills and badges.
--  Student rows are NOT seeded — those arrive through registration.
--
--  Everything here is editable in-app by a Super Admin. It is a starting point,
--  not a fixture: the HIMA structure in particular is expected to change every
--  kepengurusan, which is exactly why none of it is hardcoded in the schema.
-- ============================================================================

begin;

-- ============================================================================
--  1 · ROLE CATALOGUE
--
--  rank: lower = more authority. A holder may only assign roles with a STRICTLY
--  HIGHER rank than their own, so a Kadiv (30) can appoint an Anggota Divisi
--  (60) but never a Wakil Ketua HIMA (20). Gaps of 10 leave room for roles a
--  future kepengurusan invents without renumbering everything.
--
--  Permission keys (the full matrix is in docs/04-roles-and-permissions.md):
--    org.manage          create/edit org units
--    role.manage         edit the role catalogue
--    term.manage         academic terms
--    subject.manage      subjects
--    lecturer.manage     lecturer records
--    member.view         see member lists
--    member.approve      approve/reject join requests
--    member.manage       assign roles, end memberships
--    schedule.manage     create/edit jadwal
--    task.manage         create/edit tugas
--    task.view_progress  see who has handed in
--    announcement.post   post in read-only announcement channels
--    chat.manage         create unit rooms
--    chat.moderate       delete others' messages
--    skill.manage        curate the skill tag list
--    audit.view          read the audit log
-- ============================================================================

insert into roles (key, name_id, name_en, scope, rank, is_singleton, is_system, icon, description, permissions) values

  ('super_admin', 'Super Admin', 'Super Admin', 'system', 1, false, true, 'shield',
   'Pemelihara sistem. Mengelola struktur organisasi, peran, dan tahun akademik.',
   array['org.manage','role.manage','term.manage','subject.manage','lecturer.manage',
         'member.view','member.approve','member.manage','schedule.manage','task.manage',
         'task.view_progress','announcement.post','chat.manage','chat.moderate',
         'skill.manage','audit.view']),

  ('ketua_hima', 'Ketua Himpunan', 'Student Association President', 'program', 10, true, true, 'crown',
   'Pimpinan himpunan mahasiswa program studi.',
   array['member.view','member.approve','member.manage','announcement.post',
         'chat.manage','chat.moderate','task.view_progress','audit.view','org.manage']),

  ('wakil_ketua_hima', 'Wakil Ketua Himpunan', 'Vice President', 'program', 20, true, true, 'crown',
   'Mendampingi dan menggantikan Ketua Himpunan bila diperlukan.',
   array['member.view','member.approve','member.manage','announcement.post',
         'chat.manage','chat.moderate','task.view_progress']),

  ('sekretaris_hima', 'Sekretaris Himpunan', 'Association Secretary', 'program', 20, true, true, 'file-text',
   'Administrasi himpunan: notulen, surat, arsip, dan data anggota.',
   array['member.view','member.approve','announcement.post','subject.manage',
         'lecturer.manage','term.manage','chat.manage']),

  ('bendahara_hima', 'Bendahara Himpunan', 'Association Treasurer', 'program', 20, true, true, 'wallet',
   'Pengelolaan keuangan himpunan. (Modul kas belum ada di v1.)',
   array['member.view','announcement.post']),

  ('kadiv', 'Kepala Divisi', 'Division Head', 'division', 30, true, true, 'git-branch',
   'Memimpin satu divisi. Kewenangan terbatas pada divisinya sendiri.',
   array['member.view','member.manage','announcement.post','chat.manage','chat.moderate']),

  ('sekretaris_divisi', 'Sekretaris Divisi', 'Division Secretary', 'division', 40, true, false, 'file-text',
   'Administrasi divisi.',
   array['member.view','announcement.post']),

  ('ketua_kelas', 'Ketua Kelas', 'Class President', 'class', 40, true, true, 'users',
   'Pimpinan satu kelas. Menyetujui anggota baru dan mengelola tugas serta jadwal kelasnya.',
   array['member.view','member.approve','member.manage','schedule.manage',
         'task.manage','task.view_progress','announcement.post','chat.moderate']),

  ('sekretaris_kelas', 'Sekretaris Kelas', 'Class Secretary', 'class', 45, true, true, 'clipboard',
   'Menginput jadwal kuliah dan tugas dari dosen untuk kelasnya.',
   array['member.view','member.approve','schedule.manage','task.manage',
         'task.view_progress','announcement.post']),

  ('bendahara_kelas', 'Bendahara Kelas', 'Class Treasurer', 'class', 50, true, false, 'wallet',
   'Keuangan kelas. (Modul kas belum ada di v1.)',
   array['member.view']),

  ('anggota_divisi', 'Anggota Divisi', 'Division Member', 'division', 60, false, true, 'user',
   'Anggota aktif sebuah divisi.',
   array['member.view']),

  ('anggota', 'Anggota', 'Member', 'class', 90, false, true, 'user',
   'Mahasiswa anggota kelas. Dapat melihat jadwal, tugas, dan mengikuti obrolan.',
   array[]::text[])
;

-- ============================================================================
--  2 · ORGANISATION STRUCTURE
--
--  Structure chosen in planning: standard BPH core + divisions, all editable by
--  the Super Admin in-app. Division names below are a sensible starting set for
--  a robotics program — rename or delete them freely.
-- ============================================================================

insert into org_units (id, type, parent_id, code, name, short_name, description, icon, accent_color, sort_order)
values (
  '00000000-0000-4000-8000-000000000001',
  'program', null,
  'TRKB',
  'Teknik Robotika dan Kecerdasan Buatan',
  'TRKB',
  'Program Studi Teknik Robotika dan Kecerdasan Buatan, Universitas Komputer Indonesia.',
  'cpu', '#22d3ee', 0
);

-- Divisions under HIMA
insert into org_units (type, parent_id, code, name, short_name, description, icon, sort_order) values
  ('division', '00000000-0000-4000-8000-000000000001', 'DIV-RISTEK',
   'Divisi Riset dan Teknologi', 'Ristek',
   'Riset, lomba, dan pengembangan proyek robotika.', 'flask', 1),
  ('division', '00000000-0000-4000-8000-000000000001', 'DIV-HUMAS',
   'Divisi Hubungan Masyarakat', 'Humas',
   'Relasi eksternal, kerja sama, dan publikasi.', 'megaphone', 2),
  ('division', '00000000-0000-4000-8000-000000000001', 'DIV-ACARA',
   'Divisi Acara', 'Acara',
   'Perencanaan dan pelaksanaan kegiatan himpunan.', 'calendar', 3),
  ('division', '00000000-0000-4000-8000-000000000001', 'DIV-MEDIA',
   'Divisi Media dan Informasi', 'Media',
   'Desain, dokumentasi, dan media sosial.', 'camera', 4),
  ('division', '00000000-0000-4000-8000-000000000001', 'DIV-KADERISASI',
   'Divisi Kaderisasi', 'Kaderisasi',
   'Pembinaan dan pengembangan anggota.', 'users', 5);

-- ============================================================================
--  3 · CLASSES
--
--  Campus format: 'TRKB-<nomor kelas> <yy>'.
--    'TRKB-1 25' = Teknik Robotika dan Kecerdasan Buatan, kelas 1, angkatan 2025.
--
--  Note what is NOT stored: the semester. It is derived by semester_of() from
--  entry_year and the current academic term, so marking a new term as current is
--  the only action needed to advance every class at once.
-- ============================================================================

insert into org_units (type, parent_id, code, name, class_number, entry_year, icon, sort_order) values
  ('class', '00000000-0000-4000-8000-000000000001', 'TRKB-1 25', 'TRKB-1 Angkatan 2025', 1, 2025, 'users', 10),
  ('class', '00000000-0000-4000-8000-000000000001', 'TRKB-2 25', 'TRKB-2 Angkatan 2025', 2, 2025, 'users', 11),
  ('class', '00000000-0000-4000-8000-000000000001', 'TRKB-1 24', 'TRKB-1 Angkatan 2024', 1, 2024, 'users', 20),
  ('class', '00000000-0000-4000-8000-000000000001', 'TRKB-2 24', 'TRKB-2 Angkatan 2024', 2, 2024, 'users', 21),
  ('class', '00000000-0000-4000-8000-000000000001', 'TRKB-1 23', 'TRKB-1 Angkatan 2023', 1, 2023, 'users', 30);

-- ============================================================================
--  4 · ACADEMIC TERMS
--
--  ordinal is generated: year_start * 2 + (kind = 'genap').
--  'breaks' excludes UTS/UAS/libur weeks from generated sessions.
-- ============================================================================

insert into academic_terms (code, name, kind, year_start, start_date, end_date, week_count, is_current, breaks) values
  ('2025/2026-1', 'Semester Ganjil 2025/2026', 'ganjil', 2025,
   '2025-09-08', '2026-01-17', 16, false,
   '[{"from":"2025-10-27","to":"2025-11-01","label":"UTS"},
     {"from":"2025-12-22","to":"2026-01-03","label":"Libur Akhir Tahun"}]'::jsonb),

  ('2025/2026-2', 'Semester Genap 2025/2026', 'genap', 2025,
   '2026-02-16', '2026-06-27', 16, false,
   '[{"from":"2026-04-06","to":"2026-04-11","label":"UTS"},
     {"from":"2026-03-19","to":"2026-03-21","label":"Libur Nyepi & Idulfitri"}]'::jsonb),

  -- The CURRENT term. Exactly one row may carry is_current = true; the partial
  -- unique index academic_terms_one_current_idx enforces that.
  -- Adjust these dates to the real UNIKOM academic calendar before going live.
  ('2026/2027-1', 'Semester Ganjil 2026/2027', 'ganjil', 2026,
   '2026-09-07', '2027-01-16', 16, true,
   '[{"from":"2026-10-26","to":"2026-10-31","label":"UTS"},
     {"from":"2026-12-21","to":"2027-01-02","label":"Libur Akhir Tahun"}]'::jsonb);

-- With 2026/2027-1 current (ordinal = 2026*2 + 0 = 4052):
--   angkatan 2025 -> 4052 - 4050 + 1 = semester 3
--   angkatan 2024 -> 4052 - 4048 + 1 = semester 5
--   angkatan 2023 -> 4052 - 4046 + 1 = semester 7
--
-- Advancing the whole program to the next semester is ONE statement:
--   update academic_terms set is_current = (code = '2026/2027-2');
-- There is no per-class promotion job, and nothing to forget.

-- ============================================================================
--  5 · LECTURERS  (data only — no accounts, see docs/01)
--
--  Placeholder names. Replace with the real dosen list before going live;
--  these exist so the mockup and tests have something to reference.
-- ============================================================================

insert into lecturers (code, full_name, title_prefix, title_suffix, email, office) values
  ('DSN-01', 'Dosen Pengampu Satu',   'Dr.', 'S.T., M.T.',  null, 'Ruang Dosen TRKB'),
  ('DSN-02', 'Dosen Pengampu Dua',    null,  'S.T., M.Kom.', null, 'Ruang Dosen TRKB'),
  ('DSN-03', 'Dosen Pengampu Tiga',   'Ir.', 'M.T.',        null, 'Lab Robotika 1'),
  ('DSN-04', 'Dosen Pengampu Empat',  null,  'S.Kom., M.T.', null, 'Lab Robotika 2'),
  ('DSN-05', 'Dosen Pengampu Lima',   'Dr.', 'M.Eng.',      null, 'Ruang Dosen TRKB');

-- ============================================================================
--  6 · SUBJECTS
--
--  A representative curriculum for a robotics & AI program. default_semester
--  pre-filters the subject picker when a sekretaris enters the jadwal, which
--  removes most of the scrolling from the single most tedious data-entry task.
-- ============================================================================

insert into subjects (program_id, code, name, short_name, sks, default_semester, color) values
  ('00000000-0000-4000-8000-000000000001', 'TRKB-101', 'Matematika Teknik I',              'Matek I',    3, 1, '#60a5fa'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-102', 'Fisika Dasar',                     'Fisika',     3, 1, '#a78bfa'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-103', 'Algoritma dan Pemrograman',        'Algo',       4, 1, '#34d399'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-104', 'Pengantar Robotika',               'Pengrob',    2, 1, '#22d3ee'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-201', 'Elektronika Digital',              'Eldig',      3, 2, '#fbbf24'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-202', 'Struktur Data',                    'Strukdat',   3, 2, '#34d399'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-203', 'Mikrokontroler',                   'Mikro',      4, 2, '#f87171'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-204', 'Matematika Teknik II',             'Matek II',   3, 2, '#60a5fa'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-205', 'Menggambar Teknik dan CAD',        'CAD',        2, 2, '#c084fc'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-301', 'Sistem Kendali',                   'Siskend',    3, 3, '#22d3ee'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-302', 'Kecerdasan Artifisial',            'AI',         3, 3, '#f472b6'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-303', 'Sensor dan Aktuator',              'Sensor',     3, 3, '#fbbf24'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-304', 'Sistem Tertanam',                  'Embedded',   4, 4, '#f87171'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-305', 'Pembelajaran Mesin',               'ML',         3, 4, '#f472b6'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-306', 'Kinematika dan Dinamika Robot',    'Kinematika', 3, 4, '#22d3ee'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-401', 'Visi Komputer',                    'Komvis',     3, 5, '#a78bfa'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-402', 'Robot Operating System',           'ROS',        3, 5, '#34d399'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-403', 'Pembelajaran Mendalam',            'DL',         3, 6, '#f472b6'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-404', 'Otomasi Industri',                 'Otomasi',    3, 6, '#fb923c'),
  ('00000000-0000-4000-8000-000000000001', 'TRKB-405', 'Metodologi Penelitian',            'Metpen',     2, 6, '#94a3b8');

-- ============================================================================
--  7 · SKILL TAGS  (feature 4)
--
--  Curated so the tag list stays usable. Students may suggest additions; a
--  holder of skill.manage approves them, which is what stops twelve spellings
--  of "Arduino" from appearing.
-- ============================================================================

insert into skills (slug, name, category, color) values
  ('arduino',        'Arduino',              'embedded',    '#00979d'),
  ('esp32',          'ESP32',                'embedded',    '#e7352c'),
  ('stm32',          'STM32',                'embedded',    '#03234b'),
  ('raspberry-pi',   'Raspberry Pi',         'embedded',    '#c51a4a'),
  ('embedded-c',     'Embedded C/C++',       'embedded',    '#659ad2'),
  ('plc',            'PLC / Ladder',         'embedded',    '#fb923c'),
  ('pcb-design',     'Desain PCB',           'electronics', '#fbbf24'),
  ('soldering',      'Soldering',            'electronics', '#f59e0b'),
  ('power-elec',     'Elektronika Daya',     'electronics', '#eab308'),
  ('sensor-fusion',  'Sensor Fusion',        'electronics', '#facc15'),
  ('cad-solidworks', 'SolidWorks',           'mechanical',  '#d32f2f'),
  ('cad-fusion',     'Fusion 360',           'mechanical',  '#f97316'),
  ('3d-printing',    'Cetak 3D',             'mechanical',  '#a3e635'),
  ('machining',      'Permesinan',           'mechanical',  '#84cc16'),
  ('kinematics',     'Kinematika Robot',     'mechanical',  '#22d3ee'),
  ('ros2',           'ROS 2',                'software',    '#22314e'),
  ('python',         'Python',               'software',    '#3776ab'),
  ('cpp',            'C++',                  'software',    '#00599c'),
  ('typescript',     'TypeScript',           'software',    '#3178c6'),
  ('git',            'Git',                  'tooling',     '#f05032'),
  ('linux',          'Linux',                'tooling',     '#fcc624'),
  ('docker',         'Docker',               'tooling',     '#2496ed'),
  ('pytorch',        'PyTorch',              'ai',          '#ee4c2c'),
  ('tensorflow',     'TensorFlow',           'ai',          '#ff6f00'),
  ('opencv',         'OpenCV',               'ai',          '#5c3ee8'),
  ('yolo',           'YOLO / Deteksi Objek', 'ai',          '#00ffff'),
  ('reinforcement',  'Reinforcement Learning','ai',         '#8b5cf6'),
  ('control-pid',    'Kendali PID',          'ai',          '#06b6d4'),
  ('slam',           'SLAM',                 'ai',          '#14b8a6'),
  ('matlab',         'MATLAB / Simulink',    'tooling',     '#e16737');

-- ============================================================================
--  8 · BADGES  (feature 4, gamification)
--
--  `rule` is machine-readable so award_badges() can evaluate it — adding a badge
--  is an INSERT, not a deploy. Deliberately NO badges for chat volume: rewarding
--  message count produces noise, not help.
-- ============================================================================

insert into badges (key, name_id, name_en, description, tier, icon, rule) values
  ('first_steps',     'Langkah Pertama',   'First Steps',
   'Melengkapi profil dan menyelesaikan tugas pertama.', 'bronze', 'footprints',
   '{"type":"tasks_completed","gte":1}'::jsonb),

  ('on_time_10',      'Tepat Waktu',       'Punctual',
   '10 tugas dikumpulkan sebelum tenggat.', 'bronze', 'clock',
   '{"type":"tasks_on_time","gte":10}'::jsonb),

  ('on_time_50',      'Disiplin',          'Disciplined',
   '50 tugas dikumpulkan sebelum tenggat.', 'silver', 'clock',
   '{"type":"tasks_on_time","gte":50}'::jsonb),

  ('streak_7',        'Runtun 7 Hari',     '7-Day Streak',
   'Tujuh hari berturut-turut tanpa tugas terlambat.', 'bronze', 'flame',
   '{"type":"streak_current","gte":7}'::jsonb),

  ('streak_30',       'Runtun 30 Hari',    '30-Day Streak',
   'Tiga puluh hari berturut-turut tanpa tugas terlambat.', 'gold', 'flame',
   '{"type":"streak_current","gte":30}'::jsonb),

  ('flawless_term',   'Semester Bersih',   'Flawless Term',
   'Satu semester penuh tanpa satu pun tugas terlambat.', 'gold', 'shield-check',
   '{"type":"term_zero_late"}'::jsonb),

  ('builder_1',       'Perakit',           'Builder',
   'Memublikasikan proyek robotika pertama.', 'bronze', 'wrench',
   '{"type":"projects_public","gte":1}'::jsonb),

  ('builder_5',       'Insinyur',          'Engineer',
   'Lima proyek dipublikasikan di portofolio.', 'silver', 'cpu',
   '{"type":"projects_public","gte":5}'::jsonb),

  ('polymath',        'Serba Bisa',        'Polymath',
   'Keahlian dideklarasikan di empat kategori berbeda.', 'silver', 'sparkles',
   '{"type":"skill_categories","gte":4}'::jsonb),

  ('pengurus',        'Pengurus',          'Officer',
   'Mengemban jabatan kepengurusan kelas atau himpunan.', 'special', 'crown',
   '{"type":"held_role","scope_in":["class","division","program"]}'::jsonb),

  ('scribe',          'Juru Catat',        'Scribe',
   'Menginput 25 tugas atau jadwal untuk kelas.', 'special', 'pencil',
   '{"type":"authored_tasks","gte":25}'::jsonb);

commit;

-- ============================================================================
--  AFTER SEEDING — manual steps, in order
-- ============================================================================
--
--  1. Register yourself through the app, then promote your account:
--       update profiles set is_super_admin = true, status = 'active'
--        where nim = '<your NIM>';
--     (This is the only privileged write that must be done in SQL. Every later
--      role assignment happens in the app.)
--
--  2. Enter the jadwal for the current term — in the app, or in bulk:
--       insert into schedule_rules
--         (class_id, term_id, subject_id, lecturer_id, day_of_week,
--          start_time, end_time, room, kind)
--       values (
--         (select id from org_units      where code = 'TRKB-1 25'),
--         (select id from academic_terms where is_current),
--         (select id from subjects       where code = 'TRKB-203'),
--         (select id from lecturers      where code = 'DSN-03'),
--         1, '07:00', '09:30', 'Lab Robotika 2', 'praktikum'
--       );
--     Sessions generate automatically from the trigger on schedule_rules.
--
--  3. Verify derived semesters look right:
--       select code, entry_year, semester, semester_label, member_count
--         from class_overview order by entry_year desc, class_number;
--
--  4. Register the pg_cron jobs listed at the end of schema.sql.
--
--  5. Create the five storage buckets named in policies.sql section 13.
