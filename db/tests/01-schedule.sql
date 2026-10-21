\pset pager off
\echo '=== TEST 1: semester derived from angkatan (no manual promotion) ==='
select code, entry_year, semester, semester_label from class_overview
 order by entry_year desc, class_number;

\echo ''
\echo '=== TEST 2: schedule rule -> auto-generated sessions, breaks skipped ==='
insert into schedule_rules (class_id, term_id, subject_id, lecturer_id,
                            day_of_week, start_time, end_time, room, kind)
values (
  (select id from org_units      where code = 'TRKB-1 25'),
  (select id from academic_terms where is_current),
  (select id from subjects       where code = 'TRKB-203'),
  (select id from lecturers      where code = 'DSN-03'),
  1, '07:00', '09:30', 'Lab Robotika 2', 'praktikum'
);
select count(*) as sessions_generated,
       min(session_date) as first_meeting,
       max(session_date) as last_meeting
  from schedule_sessions;

\echo '-- UTS week (2026-04-06..11) must be absent:'
select count(*) as sessions_during_uts from schedule_sessions
 where session_date between '2026-04-06' and '2026-04-11';

\echo ''
\echo '=== TEST 3: clash detection refuses an overlapping slot ==='
do $$
begin
  insert into schedule_rules (class_id, term_id, subject_id, day_of_week,
                              start_time, end_time, room)
  values ((select id from org_units where code = 'TRKB-1 25'),
          (select id from academic_terms where is_current),
          (select id from subjects where code = 'TRKB-204'),
          1, '08:00', '10:00', 'R.301');
  raise notice 'FAIL: overlapping schedule was accepted';
exception when exclusion_violation then
  raise notice 'PASS: database refused the overlapping slot';
end $$;

\echo ''
\echo '=== TEST 4: non-overlapping slot on the same day is accepted ==='
insert into schedule_rules (class_id, term_id, subject_id, day_of_week,
                            start_time, end_time, room)
values ((select id from org_units where code = 'TRKB-1 25'),
        (select id from academic_terms where is_current),
        (select id from subjects where code = 'TRKB-204'),
        1, '10:00', '12:30', 'R.301');
select count(*) as rules_for_monday from schedule_rules where day_of_week = 1;

\echo ''
\echo '=== TEST 5: idempotent regeneration (no duplicate occurrences) ==='
select generate_sessions_for_term((select id from academic_terms where is_current)) as rows_touched;
select count(*) as total_sessions_after_regen from schedule_sessions;
