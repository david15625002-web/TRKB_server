# 03 · Data Model

Authoritative DDL: [`db/schema.sql`](../db/schema.sql). This document explains
the *reasoning* — the parts a schema file cannot tell you.

## Entity map

```
                            ┌──────────────┐
                            │  org_units   │ ◄── self-referencing tree
                            │  (program /  │     program → class
                            │   class /    │     program → division → committee
                            │   division)  │
                            └──┬────┬───┬──┘
                   ┌───────────┘    │   └────────────┐
                   ▼                ▼                ▼
          ┌─────────────┐   ┌──────────────┐  ┌────────────┐
          │ memberships │   │schedule_rules│  │ chat_rooms │
          └──┬───────┬──┘   └──────┬───────┘  └─────┬──────┘
             │       │             │ generates      │
             ▼       ▼             ▼                ▼
      ┌──────────┐ ┌───────┐ ┌──────────────────┐ ┌──────────────┐
      │ profiles │ │ roles │ │schedule_sessions │ │chat_members  │
      └──┬────┬──┘ └───────┘ └──────────────────┘ │chat_messages │
         │    │                                    │chat_reactions│
         │    └──────────────┐                     └──────────────┘
         ▼                   ▼
  ┌─────────────────┐  ┌──────────────┐      ┌───────────────┐
  │ user_skills     │  │   tasks      │─────▶│task_submissions│
  │ projects        │  └──────┬───────┘      └───────────────┘
  │ user_badges     │         │ trigger
  │ user_stats      │         ▼
  │ notification_   │  ┌────────────────────┐
  │   preferences   │─▶│ notification_jobs  │ (outbox)
  └─────────────────┘  └─────────┬──────────┘
                                 ▼
                       ┌──────────────────┐
                       │  notifications   │ (in-app inbox)
                       └──────────────────┘
```

27 tables. Below are the eight decisions that shaped them.

---

## Decision 1 · One tree table, not one table per unit kind

`org_units` holds the program, every class, every division, and any temporary
committee, distinguished by a `type` column and linked by `parent_id`.

**Why.** Permission resolution means "does this user hold the permission at this
unit *or any ancestor of it*". With one table that is a single recursive CTE
(`org_unit_ancestors`) that every policy reuses. With separate `classes` and
`divisions` tables it becomes a UNION that must be rewritten every time the
Super Admin invents a new kind of unit — and you said you want them to be able
to add and remove divisions freely.

**Cost accepted.** Class-only columns (`class_number`, `entry_year`) are NULL on
non-class rows. A CHECK constraint makes that safe rather than merely tidy:

```sql
constraint org_units_class_fields check (
  case when type = 'class'
    then class_number is not null and entry_year is not null
    else class_number is null and entry_year is null
  end
)
```

---

## Decision 2 · Classes store angkatan, never semester

`TRKB-1 25` is stored as `class_number = 1, entry_year = 2025`. The semester is
**derived**:

```sql
semester_of(entry_year) = current_term.ordinal - (entry_year * 2) + 1
where ordinal = year_start * 2 + (kind = 'genap')
```

**Why this matters more than it looks.** The obvious design is a `semester`
column on the class. That column is wrong twice a year, every year, forever,
unless somebody remembers to run an update. Deriving it means advancing the
entire program is one statement:

```sql
update academic_terms set is_current = (code = '2026/2027-2');
```

Verified: with `2026/2027-1` current, angkatan 2025 reports Semester 3,
angkatan 2024 reports Semester 5, angkatan 2023 reports Semester 7 — with no
per-class update anywhere.

**Trade-off.** A student repeating a year is still shown their angkatan's
semester. That is a display concern, solvable later with a per-student override,
and far cheaper than a schema that needs seasonal maintenance.

---

## Decision 3 · Memberships are time-bounded grants, not a `role` column

The naive design is `profiles.role text`. That cannot express any of what you
asked for:

| Requirement | Why a role column fails |
|---|---|
| Ketua Kelas of *one specific class* | A column has no scope |
| Someone is both Anggota of TRKB-1 25 **and** Kadiv Ristek | A column holds one value |
| Kepengurusan handover each periode | Overwriting destroys the history |
| "Who was Ketua HIMA in 2025?" | Unanswerable |

So: `memberships(user_id, org_unit_id, role_id, period_start, period_end, status)`.
Handover is closing one row and opening another. The record of who led what is
permanent, which is precisely the "handover amnesia" problem from `docs/01`.

Two guards worth knowing about:

- A **partial unique index** stops two people holding a singleton role
  (Ketua Kelas, Ketua HIMA) with open-ended periods in the same unit.
- A **trigger** (`check_singleton_role`) catches the harder case of two closed
  periods that overlap, which an index cannot express.

---

## Decision 4 · Roles are rows, with a rank

`roles` is data: `key`, `name_id`, `name_en`, `scope`, `rank`, `permissions[]`.
Super Admin can add "Kadiv Media" without a migration — which is exactly what
you asked for.

`rank` (lower = more authority) powers the anti-escalation rule in the RLS
policy: **you may only assign a role whose rank is strictly greater than your
own.** A Kadiv (30) can appoint an Anggota Divisi (60) but can never appoint a
Wakil Ketua HIMA (20). Ranks are spaced by 10 so a future kepengurusan can
insert roles without renumbering.

| Role | Scope | Rank |
|---|---|---|
| Super Admin | system | 1 |
| Ketua HIMA | program | 10 |
| Wakil Ketua / Sekretaris / Bendahara HIMA | program | 20 |
| Kadiv | division | 30 |
| Sekretaris Divisi · **Ketua Kelas** | division · class | 40 |
| Sekretaris Kelas | class | 45 |
| Bendahara Kelas | class | 50 |
| Anggota Divisi | division | 60 |
| Anggota | class | 90 |

---

## Decision 5 · Schedules split into rules and occurrences

```
schedule_rules      "Mikrokontroler, Senin 07:00–09:30, Lab Robotika 2, weeks 1–16"
      │ generate_sessions_for_rule()
      ▼
schedule_sessions   16 Feb · 23 Feb · 2 Mar · … (one row per real meeting)
```

**Why not one table.** Real semesters are messy in ways a recurrence rule cannot
absorb: *"minggu depan pindah ke Lab 3"*, *"dosen sakit, kelas dibatalkan"*,
*"kuliah pengganti Sabtu"*. Editing the recurring rule to express a one-week
change corrupts the definition for all 16 weeks.

Generating occurrences also turns every read into a plain indexed query.
"What do I have today" is `where class_id = ? and session_date = ?` — no
recurrence arithmetic on a phone.

**The guard that makes it safe.** `schedule_sessions.is_override` marks any
occurrence a human edited. Regeneration skips those rows:

```sql
on conflict (rule_id, session_date) do update
   set ... where schedule_sessions.is_override = false
```

Verified: regenerating a term twice produces 30 sessions both times, not 60,
and the UTS break week is correctly absent.

**Clash detection is in the database**, not the form validator:

```sql
exclude using gist (
  class_id with =, day_of_week with =,
  (timerange_from_times(start_time, end_time)) with &&
) where (is_active)
```

Verified: a 08:00–10:00 slot is refused when 07:00–09:30 already exists on that
weekday; 10:00–12:30 is accepted. The tired sekretaris entering a jadwal at
midnight gets caught by Postgres, not by a reviewer three weeks later.

---

## Decision 6 · A task's definition and a student's progress are different tables

`tasks` is shared. `task_submissions` is per-student.

This is not normalisation for its own sake — it is a permission boundary. There
is **no RLS policy** anywhere that lets a pengurus write another student's
submission row. Ketua Kelas can *read* class progress (`task.view_progress`) to
chase submissions, but cannot mark someone else done. Your checkbox is yours.

`was_late` and `submitted_at` are stamped by a trigger from the **server** clock,
because a client-supplied timestamp is a self-reported grade.

---

## Decision 7 · Notifications use an outbox

Three tables, three jobs:

| Table | Role |
|---|---|
| `notification_preferences` | What each person wants, per channel |
| `notification_jobs` | **The outbox.** One row per (person, event, offset, channel) |
| `notifications` | The in-app inbox behind the bell icon |

The outbox is why reminders are reliable. Enqueueing is a pure SQL transaction;
delivery is a separate drain that may fail and retry. The guarantee lives in one
column:

```sql
dedupe_key text not null unique
-- 'task:<uuid>:<user>:1440:push'
```

A cron re-run, a crashed dispatcher, a duplicate webhook — none can double-send,
because the second insert collides. Moving a deadline reschedules the existing
rows instead of adding new ones. Verified: 10 jobs before a due-date change,
10 after.

**Quiet hours defer, never drop.** A dropped deadline reminder is a missed
deadline, which defeats the product's entire purpose:

| Scheduled | Quiet 22:00–06:00 | Result |
|---|---|---|
| 23:30 | inside | → 06:00 next day |
| 03:00 | inside | → 06:00 same day |
| 18:00 | outside | unchanged |

**Email is digest-only by default** — a deliberate product decision forced by
the free tier's 3,000 sends/month (see `docs/02`). Jobs with an offset under 24h
never create an email row.

---

## Decision 8 · Soft delete only where history is load-bearing

| Table | Delete style | Why |
|---|---|---|
| `tasks` | soft (`deleted_at`) | A reminder already sent must stay explainable |
| `chat_messages` | soft, **body blanked by trigger** | Replies and read state must not dangle, but "hapus" has to actually remove the content |
| `memberships` | never (set `period_end`) | The institutional record |
| `chat_reactions`, `push_subscriptions` | hard | No history worth keeping |

On chat deletion specifically: hiding a message behind a UI flag while the text
still sits in the row is a privacy failure dressed as a feature. The
`redact_deleted_message` trigger nulls `body`, `attachments` and `mentions`.

---

## Indexing notes

Partial indexes everywhere the query always filters the same way:

```sql
create index tasks_class_due_idx on tasks (class_id, due_at)
  where deleted_at is null and is_published;

create index notification_jobs_due_idx on notification_jobs (scheduled_at)
  where state = 'queued';
```

The dispatcher's drain query touches only queued rows, so the index holds only
queued rows — it stays small even after a year of sent history.

Trigram GIN indexes on `profiles.full_name`, `subjects.name`, `org_units.name`
and `chat_messages.body` give typo-tolerant search without a search service.

## What is deliberately absent

| Not modelled | Why |
|---|---|
| Attendance | Out of scope for v1 (`docs/01`); needs dosen buy-in or location trust |
| Grades | Sensitive academic record; wrong data harms a real student |
| Kas / payments | Money invites disputes and liability |
| Message read receipts per message | `chat_members.last_read_at` is enough and costs one row, not one row per message per person |
| File versioning | Nobody needs v3 of a laporan in a class app |
