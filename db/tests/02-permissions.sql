\pset pager off
-- Supabase's client role. RLS is NOT enforced for superusers or table owners,
-- so the whole test must run as a non-owner role or it proves nothing.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;
grant usage on schema public, auth to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all tables in schema auth to authenticated;
grant execute on all functions in schema public, auth to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Three people:
--   budi  = Ketua Kelas of TRKB-1 25
--   sari  = plain Anggota of TRKB-1 25
--   dewi  = Sekretaris Kelas of TRKB-2 25   (a DIFFERENT class)
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'budi@mahasiswa.unikom.ac.id'),
  ('22222222-2222-4222-8222-222222222222', 'sari@mahasiswa.unikom.ac.id'),
  ('33333333-3333-4333-8333-333333333333', 'dewi@mahasiswa.unikom.ac.id');

insert into profiles (id, nim, full_name, email, status, entry_year) values
  ('11111111-1111-4111-8111-111111111111', '15625001', 'Budi', 'budi@mahasiswa.unikom.ac.id', 'active', 2025),
  ('22222222-2222-4222-8222-222222222222', '15625002', 'Sari', 'sari@mahasiswa.unikom.ac.id', 'active', 2025),
  ('33333333-3333-4333-8333-333333333333', '15625003', 'Dewi', 'dewi@mahasiswa.unikom.ac.id', 'active', 2025);

insert into memberships (user_id, org_unit_id, role_id, status, is_primary) values
  ('11111111-1111-4111-8111-111111111111',
   (select id from org_units where code='TRKB-1 25'),
   (select id from roles where key='ketua_kelas'), 'active', true),
  ('22222222-2222-4222-8222-222222222222',
   (select id from org_units where code='TRKB-1 25'),
   (select id from roles where key='anggota'), 'active', true),
  ('33333333-3333-4333-8333-333333333333',
   (select id from org_units where code='TRKB-2 25'),
   (select id from roles where key='sekretaris_kelas'), 'active', true);

\echo '=== TEST 6: permission scoping via has_perm() ==='
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
select 'budi / own class TRKB-1 25' as subject,
       has_perm('task.manage', (select id from org_units where code='TRKB-1 25')) as allowed
union all
select 'budi / OTHER class TRKB-2 25',
       has_perm('task.manage', (select id from org_units where code='TRKB-2 25'))
union all
select 'sari (anggota) / own class',
       (select has_perm('task.manage', (select id from org_units where code='TRKB-1 25'))
          from (select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true)) _);
reset role;

\echo ''
\echo '=== TEST 7: Ketua Kelas CAN create a task in their own class ==='
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
do $$ begin
  insert into tasks (class_id, term_id, subject_id, title, due_at, created_by)
  values ((select id from org_units where code='TRKB-1 25'),
          (select id from academic_terms where is_current),
          (select id from subjects where code='TRKB-203'),
          'Laporan Praktikum Mikrokontroler', now() + interval '3 days',
          '11111111-1111-4111-8111-111111111111');
  raise notice 'PASS: ketua kelas created a task in their own class';
exception when others then
  raise notice 'FAIL: % (%)', sqlerrm, sqlstate;
end $$;

\echo ''
\echo '=== TEST 8: Ketua Kelas CANNOT create a task in another class (the key claim) ==='
do $$ begin
  insert into tasks (class_id, term_id, subject_id, title, due_at)
  values ((select id from org_units where code='TRKB-2 25'),
          (select id from academic_terms where is_current),
          (select id from subjects where code='TRKB-203'),
          'Tugas sabotase kelas lain', now() + interval '3 days');
  raise notice 'FAIL: RLS allowed a cross-class write!';
exception when insufficient_privilege then
  raise notice 'PASS: RLS blocked the cross-class write';
end $$;

\echo ''
\echo '=== TEST 9: plain Anggota CANNOT create a task at all ==='
set request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
do $$ begin
  insert into tasks (class_id, term_id, subject_id, title, due_at)
  values ((select id from org_units where code='TRKB-1 25'),
          (select id from academic_terms where is_current),
          (select id from subjects where code='TRKB-203'),
          'Tugas palsu dari anggota', now() + interval '3 days');
  raise notice 'FAIL: an anggota created a task!';
exception when insufficient_privilege then
  raise notice 'PASS: RLS blocked the anggota';
end $$;
reset role;
