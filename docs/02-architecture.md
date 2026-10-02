# 02 · Architecture

## System overview

```
                        ┌──────────────────────────────────────┐
                        │            CLIENTS                   │
                        │                                      │
                        │  PWA (installed to home screen)      │
                        │  Desktop browser (pengurus work)      │
                        │  [v1.1] Capacitor .apk wrapper       │
                        └───────────────┬──────────────────────┘
                                        │ HTTPS / WSS
                                        ▼
        ┌───────────────────────────────────────────────────────────┐
        │              Next.js 15 (App Router) on Vercel            │
        │                                                           │
        │  Server Components ──── read-heavy pages (jadwal, tugas)  │
        │  Server Actions ─────── mutations (create task, approve)  │
        │  Route Handlers ─────── /api/cron/*, /api/push/*, webhooks │
        │  Client Components ──── chat, countdowns, theme switcher  │
        │  Service Worker ─────── offline shell, Web Push receiver  │
        └───────┬───────────────────────────────┬───────────────────┘
                │ supabase-js (RLS as user)     │ service-role key
                │                               │ (server only, never shipped)
                ▼                               ▼
        ┌──────────────────────────────────────────────────────────┐
        │                      SUPABASE                            │
        │                                                          │
        │  Auth ──────── magic link + Google OAuth, campus domain  │
        │  PostgreSQL ── all domain tables, RLS on every one       │
        │  Realtime ──── chat_messages, notifications (per-user)   │
        │  Storage ───── avatars, banners, chat images, project    │
        │                covers (public read, owner write)         │
        │  pg_cron ───── session generation, reminder enqueue      │
        └──────────────────────────────────────────────────────────┘
                │                               │
                ▼                               ▼
        ┌───────────────────┐         ┌──────────────────────────┐
        │  Web Push (VAPID) │         │  Email (Resend / Brevo)  │
        │  → Android/Chrome │         │  → digest + fallback     │
        │  → iOS 16.4+ PWA  │         └──────────────────────────┘
        └───────────────────┘
```

## Technology choices and why

| Layer | Choice | Reasoning | Rejected alternative |
|-------|--------|-----------|---------------------|
| Client | **Next.js 15 + TypeScript**, App Router | One codebase serves the PWA and the admin screens. Server Components mean the heavy jadwal/tugas pages ship almost no JS — important on campus WiFi. | SPA + separate API: two deploys, worse first paint, no benefit here. |
| Styling | **Tailwind CSS v4 + CSS custom properties** | Themes are CSS variables, so switching preset is one attribute on `<html>` — no re-render, no flash. Tailwind keeps the markup honest. | CSS-in-JS: runtime cost and awkward theming. |
| State | **Server state via RSC + TanStack Query** for realtime surfaces only | Most screens need no client state at all. Only chat and notifications genuinely do. | Global Redux/Zustand store: solving a problem we don't have. |
| Backend | **Supabase** | Postgres with RLS *is* the authorisation layer, which is exactly what a scoped role hierarchy needs. Auth, realtime, storage and cron in the free tier. | Custom NestJS: you'd rewrite auth, sockets, and storage before writing one feature. Firebase: NoSQL makes the schedule/role joins painful. |
| Database | **PostgreSQL 15** | Recursive CTEs for the org tree, `tstzrange` + exclusion constraints for schedule clash detection, generated columns, and real foreign keys. | MySQL: weaker recursive/range support. Mongo: no. |
| Auth | **Supabase Auth** — magic link + Google, restricted to campus domain | Nobody manages passwords. Domain restriction is the first identity gate; Ketua approval is the second. | Rolling our own: a liability, not a feature. |
| Realtime | **Supabase Realtime** (Postgres logical replication) | Chat messages broadcast straight from the table that stores them, with RLS applied to the stream. No second system to keep in sync. | Socket.io server: another process to host and secure. |
| Push | **Web Push / VAPID** | Free, no store approval, works on Android Chrome and iOS 16.4+ once installed to home screen. | FCM-only: ties us to a Firebase project we otherwise don't need. |
| Email | **Resend** (fallback Brevo) | Clean API, generous free tier, good deliverability for transactional mail. | SMTP via Gmail: rate limits and spam folders. |
| Scheduling | **pg_cron inside Supabase** + a Vercel Cron safety net | Reminder enqueueing is a `SELECT … INSERT`; it belongs next to the data. The Vercel cron is a watchdog that alerts if the queue stalls. | External worker: more moving parts, more to pay for. |
| Mobile wrapper | **Capacitor** (v1.1, only if asked) | Wraps the same PWA into a real `.apk` with native notification permissions. Zero rewrite. | Flutter/React Native: a second codebase for no new capability. |

## Why RLS instead of application-layer checks

This is the single most important architectural decision, so it gets its own
section.

The role system is *scoped*: Ketua Kelas of `TRKB-1 25` may edit that class's
tasks and nothing else. There are two places to enforce that:

- **In application code** — every query must remember to filter by scope. One
  forgotten `WHERE` in one Server Action, eighteen months from now, and a
  second-semester ketua wipes semester six's schedule.
- **In the database** — the policy is attached to the *table*. Every query from
  every code path, including the SQL console and any future mobile client, is
  filtered whether the developer remembered or not.

We choose the database. The application still hides buttons the user can't use,
but that is **UX, not security**. The rule is written once in
`db/policies.sql` and tested with pgTAP.

Consequence to accept: debugging "why can't I see this row" means reading
policies, not application code. `docs/04` documents every policy for that reason.

## Repository layout (planned)

```
TRKB_server/
├── README.md
├── docs/                     ← this design set
├── db/
│   ├── schema.sql            ← full DDL (authoritative during design)
│   ├── policies.sql          ← permission functions + RLS
│   └── seed.sql              ← sample TRKB data
├── mockup/                   ← clickable HTML prototype, no build step
│
└── app/                      ← [Phase 1] the real application
    ├── supabase/
    │   ├── migrations/       ← numbered, generated from db/*.sql
    │   └── functions/        ← edge functions: send-push, send-email
    ├── src/
    │   ├── app/
    │   │   ├── (auth)/       ← login, register, pending-approval
    │   │   ├── (app)/
    │   │   │   ├── beranda/      ← dashboard
    │   │   │   ├── jadwal/       ← schedule
    │   │   │   ├── tugas/        ← tasks
    │   │   │   ├── obrolan/      ← chat
    │   │   │   ├── organisasi/   ← org tree + role management
    │   │   │   ├── profil/[nim]/ ← public profile
    │   │   │   └── pengaturan/   ← settings, notif prefs, theme
    │   │   └── api/
    │   │       ├── cron/generate-sessions/
    │   │       ├── cron/enqueue-reminders/
    │   │       ├── cron/dispatch/
    │   │       └── push/subscribe/
    │   ├── components/
    │   │   ├── ui/           ← primitives (Panel, Chip, StatusLED, Countdown)
    │   │   └── feature/      ← ScheduleGrid, TaskCard, RoomList, ThemePicker
    │   ├── lib/
    │   │   ├── supabase/     ← server + browser clients
    │   │   ├── permissions.ts    ← mirrors SQL, for UI gating only
    │   │   ├── schedule.ts       ← recurrence expansion, clash detection
    │   │   ├── reminders.ts      ← offset arithmetic, quiet hours
    │   │   └── csv/              ← jadwal importer + column mapping
    │   ├── styles/
    │   │   ├── tokens.css        ← the 4 theme presets
    │   │   └── globals.css
    │   └── i18n/{id,en}.json
    ├── public/
    │   ├── manifest.webmanifest
    │   └── sw.js
    └── tests/
        ├── db/               ← pgTAP: one test per RLS policy
        └── e2e/              ← Playwright: the four critical user journeys
```

## Request paths, concretely

**Reading the dashboard (most common action).** Server Component calls
`supabase.rpc('get_beranda', { for_date })` with the user's JWT. One round trip
returns today's sessions, next 7 days of tasks, unread counts. RLS has already
restricted everything to the classes the user belongs to. Rendered HTML streams
to the phone; almost no JS hydrates.

**Creating a task (a privileged write).** Client submits to a Server Action.
The action validates with Zod, then inserts as the *user* (not service role), so
the RLS policy `tasks_insert` is the authority on whether this person may write
to that class. The insert fires a trigger that enqueues notification jobs for
every member of the class. The action returns, the UI revalidates.

**A chat message.** Client inserts into `chat_messages` directly through
supabase-js. RLS checks room membership. Realtime broadcasts the row to the
other subscribed members — no server hop. Optimistic render on send; reconcile
on the broadcast echo.

**A reminder firing.** `pg_cron` runs `enqueue_due_reminders()` every 5 minutes,
which materialises rows into `notification_jobs` with a unique `dedupe_key` so a
re-run can never double-send. A second cron calls an Edge Function that drains
the queue to Web Push and email, writing `sent_at` or an error back.

## Scaling envelope

Sized for ~250 students, ~12 classes, ~40 subjects:

| Metric | Estimate | Free-tier limit | Headroom |
|--------|----------|-----------------|----------|
| Rows, schedule_sessions | 12 classes × 8 subj × 16 wk ≈ 1,500/term | 500 MB total | Vast |
| Rows, chat_messages | ~300/day ≈ 110k/year | 500 MB total | Fine with image data in Storage, not the DB |
| Realtime concurrent | peak ~60 | 200 | OK |
| Push sends | ~250/day | unlimited (self-hosted VAPID) | OK |
| Email sends | digests only, ~250/day | 3,000/mo on Resend free | **Tight** — so email is digest-first, not per-event |

The email row is why `05` makes email a daily digest by default rather than a
per-reminder channel. That is a free-tier constraint driving a product decision,
and it's better to write it down than to discover it when sends start bouncing.

## Security posture

- Service-role key exists **only** in server environment variables. Any import
  of it into a client bundle must fail CI.
- Storage buckets: public read for avatars/banners/project covers; writes
  restricted to the owning user's folder. Chat images live in a private bucket
  served through signed URLs, because a leaked chat image URL is a real privacy
  problem.
- Rate limits on the writes that can be abused: task creation, chat messages,
  join requests, approvals.
- `audit_log` records who changed structural data (roles, schedules, terms).
  Reads are deliberately not logged — logging every read of a classmate's
  profile would be both useless and creepy.
- Uploaded files are checked by magic bytes, not by filename extension.
