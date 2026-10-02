# 05 · Notifications & Reminders

This is the feature the whole product exists for. Everything else — schedules,
roles, chat — is infrastructure that makes a correct, timely reminder possible.

## The insight

WhatsApp notifies you when a message is **sent**. Coursework needs a notification
when a deadline is **near**. No chat app can do the second thing, which is why no
amount of group-chat discipline solves the problem.

## Pipeline

```
  ┌──────────────┐
  │ task created │  Ketua/Sekretaris Kelas publishes a tugas
  │ or due_at    │
  │ changed      │
  └──────┬───────┘
         │ AFTER INSERT/UPDATE trigger
         ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ enqueue_task_reminders(task_id)                              │
  │                                                              │
  │  for each ACTIVE member of the class:                        │
  │    skip if subject or class is muted by that person          │
  │    for each offset in their task_offsets (default 1440, 180):│
  │      when = due_at − offset                                  │
  │      if offset ≥ 1440: snap to their digest hour (18:00 WIB) │
  │      skip if already past                                    │
  │      when = shift_out_of_quiet_hours(when, …)                │
  │      for each enabled channel:                               │
  │        INSERT … ON CONFLICT (dedupe_key) DO UPDATE           │
  └──────┬───────────────────────────────────────────────────────┘
         ▼
  ┌──────────────────────┐    pg_cron every minute
  │  notification_jobs   │ ◄────────────────────────┐
  │     (the outbox)     │                          │
  └──────┬───────────────┘                          │
         │ state='queued' and scheduled_at <= now() │
         ▼                                          │
  ┌──────────────────────────────────┐              │
  │ Edge Function: dispatch          │──────────────┘
  │   inapp → INSERT notifications   │
  │   push  → Web Push (VAPID)       │
  │   email → Resend                 │
  │   write sent_at or last_error    │
  └──────────────────────────────────┘
```

## Why an outbox and not "send it now"

Sending inside the transaction that creates the task would mean: a push failure
rolls back the task, or the task commits and the push is lost. Neither is
acceptable.

The outbox makes enqueueing a pure SQL write and delivery a separate, retryable
step. The entire correctness guarantee rests on one column:

```sql
dedupe_key text not null unique    -- 'task:<uuid>:<user>:1440:push'
```

| Scenario | Outcome |
|---|---|
| Cron fires twice | Second insert collides on `dedupe_key`. No duplicate. |
| Dispatcher crashes after sending, before writing `sent_at` | Row stays `queued`, retried. **One duplicate possible** — see below. |
| Deadline moved | Queued rows cancelled, then re-upserted with new times. Verified: 10 jobs before, 10 after. |
| Task deleted | Queued rows set to `cancelled`. |
| Class cancelled | Session jobs cancelled + an in-app notice sent. Verified: 4 jobs cancelled, 2 students informed. |

**Honest statement of the guarantee: at-least-once, not exactly-once.** A crash
in the window between the push API returning 201 and the `UPDATE … sent_at`
committing will re-send on retry. Making that window disappear requires
distributed transactions against a third-party HTTP API, which is not worth it
here. A student occasionally seeing the same reminder twice is a minor annoyance;
*never* seeing it is the failure we are actually engineering against.

## Default offsets, and why

| Event | Default | Reasoning |
|---|---|---|
| Task | **H-1** at 18:00 WIB | Evening, when students plan tomorrow. A reminder at exactly 24h-before could land at 03:00 and be swiped away in sleep. |
| Task | **H-3 hours** | The last practical moment to actually do something. |
| Class | **30 min before** | Enough to walk to Lab Robotika; not so early you forget again. |

The H-1 snap-to-digest-hour is the subtle part:

```sql
if v_offset >= 1440 then
  v_local := date_trunc('day', (t.due_at at time zone v_member.timezone))
             - make_interval(days => v_offset / 1440)
             + make_interval(hours => v_member.daily_digest_hour);
  v_when := v_local at time zone v_member.timezone;
end if;
```

`v_local` **must** be declared `timestamp`, not `timestamptz`. This was a real
bug: `due_at at time zone 'Asia/Jakarta'` yields a *naive* timestamp, and
assigning it to a `timestamptz` variable made Postgres reinterpret it in the
server's timezone, then convert again on the way out. Every H-1 reminder fired
at **08:00 WIB instead of 18:00**. It applied clean, it passed review by reading,
and it was wrong — it took running the code to find.

Verified after the fix:

```
 channel | offset_min | title                                    | fires_at_wib
---------+------------+------------------------------------------+--------------
 push    |       1440 | Besok: Laporan Praktikum Mikrokontroler   | 04 Oct 18:00
 push    |        180 | Segera: Laporan Praktikum Mikrokontroler  | 05 Oct 09:37
```

## Quiet hours defer, never drop

A suppressed deadline reminder is a missed deadline. `shift_out_of_quiet_hours()`
moves delivery to the end of the quiet window, handling the midnight-crossing
case (22:00–06:00) separately from the simple case (01:00–06:00):

| Scheduled | Quiet window | Result |
|---|---|---|
| 23:30 | 22:00–06:00 | 06:00 next morning |
| 03:00 | 22:00–06:00 | 06:00 same morning |
| 18:00 | 22:00–06:00 | unchanged |

Verified in `db/tests/03-notifications.sql`.

## Channels

| Channel | Transport | Default | Notes |
|---|---|---|---|
| **In-app** | row in `notifications`, streamed by Realtime | on | The bell icon. Always on; costs nothing. |
| **Push** | Web Push / VAPID | on | Android Chrome works immediately. **iOS requires the PWA to be added to the home screen** (iOS 16.4+) — the onboarding must say this explicitly or iPhone users will silently get nothing. |
| **Email** | Resend | digest only | Free tier is 3,000/month. At ~250 students that is ~12 sends per student per month, so per-event email is impossible. Only offsets ≥ 24h create an email job. Verified: offset 1440 → 2 email jobs; offset 180 → 0. |

### Channel adapters, for WhatsApp later

`notification_jobs.channel` is an enum and the dispatcher switches on it. Adding
WhatsApp or Telegram means: add an enum value, add a case in the dispatcher, add
a preference toggle. No change to the enqueueing logic, which is where all the
timing subtlety lives.

Telegram would be the cheap, reliable choice (free Bot API, no number risk).
WhatsApp needs the paid Business API; the unofficial libraries get numbers
banned, which would be a bad thing to do to a student's personal phone number.

## Suppression rules

A reminder is **not** sent when:

1. The task is `is_published = false` (a draft — a sekretaris can prepare at
   02:00 without waking forty people).
2. The student muted that subject or that class.
3. The channel is disabled in their preferences.
4. The computed time is already in the past.
5. The task was soft-deleted, or the session cancelled or moved.
6. It is an email job with an offset under 24 hours.

A reminder **is still sent** when the student has already marked the task done —
deliberately. The in-app list shows completed tasks differently, but suppressing
the push would mean trusting a self-reported checkbox to silence a real deadline.
*(Flagged as an open question in `docs/11`: "done" suppression may be worth
adding once there is real usage data.)*

## Rate limiting and anti-spam

| Protection | Mechanism |
|---|---|
| One pengurus spamming tasks | Rate limit on task creation (app layer) + audit log |
| Reminder storms from a bulk CSV import | Import creates tasks as drafts; publishing is one explicit action |
| Mass @everyone in chat | `mentions[]` capped; announcement channels are read-only for non-pengurus |
| Dead push endpoints | `failed_count` incremented; subscription deleted on 404/410 |

## Scheduled jobs

Registered in Supabase (`pg_cron`), times UTC, WIB = UTC+7:

| Job | Schedule | Purpose |
|---|---|---|
| `dispatch-notifications` | every minute | Drain the outbox |
| `enqueue-class-reminders` | every 15 min | Rolling 48h horizon of class reminders |
| `generate-sessions-nightly` | 01:00 WIB | Catch up any ungenerated sessions |
| `mark-held-sessions` | every 30 min | Flip finished sessions to `held` |
| `prune-notification-jobs` | 02:30 WIB Sunday | Delete sent/cancelled rows older than 60 days |

Class reminders are enqueued on a **rolling horizon**, not for the whole
semester: one term across 12 classes would otherwise materialise roughly 60,000
rows, most of which would never be read.

### Watchdog

A Vercel Cron hits `/api/cron/health` every 15 minutes and checks:

```sql
select count(*) from notification_jobs
 where state = 'queued' and scheduled_at < now() - interval '10 minutes';
```

Non-zero means the dispatcher is stuck. **Silent reminder failure is the worst
possible bug in this product** — nobody files a ticket for a notification that
never arrived; they just quietly stop trusting the app.

## Copy

Indonesian, short enough to read on a lock screen without expanding.

| Event | Title | Body |
|---|---|---|
| Task H-1 | `Besok: Laporan Praktikum Mikrokontroler` | `Mikrokontroler · dikumpulkan 05 Oct 2026 23:59` |
| Task H-3h | `Segera: Laporan Praktikum Mikrokontroler` | `Mikrokontroler · dikumpulkan 05 Oct 2026 23:59` |
| Class soon | `Mikrokontroler · 30 menit lagi` | `Ruang Lab Robotika 2` |
| Class cancelled | `Kelas dibatalkan` | `Dosen sakit` |
| Approval needed | `1 anggota menunggu persetujuan` | `Budi (15625001) ingin bergabung ke TRKB-1 25` |
| Approved | `Kamu diterima di TRKB-1 25` | `Selamat bergabung.` |

The subject name goes in the body, not the title: on a locked Android screen the
title truncates around 40 characters, and the task name is what identifies it.
