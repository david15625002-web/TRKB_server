\pset pager off
\echo '=== TEST 10: H-1 reminders were enqueued for every class member ==='
select nj.channel,
       (nj.payload->>'offset_minutes')::int as offset_min,
       p.full_name,
       nj.title,
       to_char(nj.scheduled_at at time zone 'Asia/Jakarta', 'DD Mon HH24:MI') as fires_at_wib,
       nj.state
  from notification_jobs nj
  join profiles p on p.id = nj.user_id
 where nj.source_type = 'task'
 order by p.full_name, offset_min desc, nj.channel;

\echo ''
\echo '-- The H-1 job must fire at 18:00 WIB the day before, not at a random hour:'
select distinct to_char(scheduled_at at time zone 'Asia/Jakarta', 'HH24:MI') as h1_local_time
  from notification_jobs
 where (payload->>'offset_minutes')::int = 1440;

\echo ''
\echo '=== TEST 11: email is digest-only (no email job for the 3-hour offset) ==='
select (payload->>'offset_minutes')::int as offset_min,
       count(*) filter (where channel='email') as email_jobs,
       count(*) filter (where channel='push')  as push_jobs,
       count(*) filter (where channel='inapp') as inapp_jobs
  from notification_jobs where source_type='task'
 group by 1 order by 1 desc;

\echo ''
\echo '=== TEST 12: moving the deadline reschedules rather than duplicating ==='
select count(*) as jobs_before from notification_jobs where source_type='task';
update tasks set due_at = due_at + interval '2 days'
 where title = 'Laporan Praktikum Mikrokontroler';
select count(*) as jobs_after_due_change,
       count(*) filter (where state='queued')    as queued,
       count(*) filter (where state='cancelled') as cancelled
  from notification_jobs where source_type='task';

\echo ''
\echo '=== TEST 13: per-subject mute suppresses that student only ==='
update notification_preferences
   set muted_subject_ids = array[(select id from subjects where code='TRKB-203')]
 where user_id = '22222222-2222-4222-8222-222222222222';
delete from notification_jobs;
select enqueue_task_reminders((select id from tasks where title='Laporan Praktikum Mikrokontroler')) as jobs_created;
select p.full_name, count(*) as jobs
  from notification_jobs nj join profiles p on p.id = nj.user_id
 group by 1 order by 1;

\echo ''
\echo '=== TEST 14: quiet hours DEFER (never drop) a reminder ==='
select to_char(shift_out_of_quiet_hours(
         '2026-03-02 23:30+07'::timestamptz, '22:00'::time, '06:00'::time, 'Asia/Jakarta')
       at time zone 'Asia/Jakarta', 'DD Mon HH24:MI') as "23:30 deferred to",
       to_char(shift_out_of_quiet_hours(
         '2026-03-02 03:00+07'::timestamptz, '22:00'::time, '06:00'::time, 'Asia/Jakarta')
       at time zone 'Asia/Jakarta', 'DD Mon HH24:MI') as "03:00 deferred to",
       to_char(shift_out_of_quiet_hours(
         '2026-03-02 18:00+07'::timestamptz, '22:00'::time, '06:00'::time, 'Asia/Jakarta')
       at time zone 'Asia/Jakarta', 'DD Mon HH24:MI') as "18:00 unchanged";

\echo ''
\echo '=== TEST 15: cancelling a class revokes its pending reminders ==='
select enqueue_upcoming_class_reminders(interval '400 days') as class_jobs_created;
select count(*) as queued_session_jobs from notification_jobs
 where source_type='session' and state='queued';
update schedule_sessions set status='cancelled', status_note='Dosen sakit'
 where id = (select id from schedule_sessions
              where status='scheduled' and starts_at > now() order by starts_at limit 1);
select count(*) as cancelled_session_jobs from notification_jobs
 where source_type='session' and state='cancelled';
select count(*) as students_informed from notifications where kind='session_cancelled';

\echo ''
\echo '=== TEST 16: privilege-escalation guard on profiles ==='
set role authenticated;
set request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
update profiles set is_super_admin = true, status = 'active', bio = 'Halo!'
 where id = '22222222-2222-4222-8222-222222222222';
reset role;
select full_name, is_super_admin as got_admin, bio as bio_change_kept
  from profiles where id = '22222222-2222-4222-8222-222222222222';
