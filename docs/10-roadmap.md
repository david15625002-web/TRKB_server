# 10 · Roadmap

Estimates assume **one student working part-time around coursework** — roughly
8–12 hours a week. They are deliberately not optimistic; a plan you miss by 300%
is worse than no plan.

## Phase 0 · Design — ✅ done

This repository: specifications, a complete PostgreSQL schema with RLS verified
against a live server, and a clickable prototype verified in a real browser.

## Phase 1 · Foundation — ~2 weeks

**Goal: you can sign in, and the database refuses what it should refuse.**

- [ ] `create-next-app` with TypeScript, Tailwind v4, App Router
- [ ] Supabase project; `db/*.sql` converted into numbered migrations
- [ ] Auth: magic link + Google, restricted to `@mahasiswa.unikom.ac.id`
- [ ] Registration → pending → approval screens
- [ ] Theme engine: port `tokens.css`, server-render the user's preset so there
      is no flash of the wrong theme
- [ ] i18n scaffolding (`id` default, `en` toggle)
- [ ] pgTAP: one test per RLS policy, plus a negative test for each escalation
      path in `docs/04`
- [ ] CI: typecheck, lint, pgTAP on every push

**Done when:** two test accounts exist, one is approved, one is pending, and the
pending one can read nothing. This is the only phase with no visible payoff —
resist shortening it, because every later phase assumes it is solid.

## Phase 2 · Schedule — ~2 weeks

**Goal: a student opens the app and sees today's classes.**

- [ ] Jadwal: agenda (phone), week grid (desktop)
- [ ] Schedule rule editor for Sekretaris
- [ ] CSV/Excel import with the three-phase flow from `docs/09`
- [ ] Per-session override: room change, cancel, kuliah pengganti
- [ ] Beranda: next-class countdown
- [ ] `.ics` feed per class

**Done when:** your own class's real jadwal is in it, and you use it instead of a
screenshot of the PDF.

## Phase 3 · Tasks & reminders — ~2 weeks ⭐

**Goal: the feature the product exists for.**

- [ ] Task CRUD for Ketua/Sekretaris Kelas
- [ ] Personal completion tracking
- [ ] Web Push: VAPID keys, service worker, subscription management
- [ ] Notification preferences UI (offsets, quiet hours, per-subject mute)
- [ ] Edge Function dispatcher + the five `pg_cron` jobs
- [ ] Email digest via Resend
- [ ] Watchdog on queue depth

**Done when:** a reminder you did not manually trigger arrives on your phone at
18:00 the day before a real deadline.

**This is the make-or-break phase.** If you ship only Phases 1–3, you have a
product worth using. Everything after is improvement.

## Phase 4 · Roles & organisation — ~1.5 weeks

- [ ] Org tree viewer
- [ ] Role assignment with the rank guard
- [ ] Approval queue with push to Ketua/Sekretaris
- [ ] Handover flow (close a period, open the next)
- [ ] Super Admin: terms, subjects, lecturers, divisions
- [ ] Audit log viewer

Much of this is already enforced in the database; this phase is mostly UI.

## Phase 5 · Profiles & portfolio — ~2 weeks

- [ ] Profile edit: avatar, banner, bio, links, pronouns
- [ ] Skill picker + curation queue
- [ ] Project CRUD with collaborators
- [ ] Program-wide project browse, filter by skill
- [ ] Badge evaluation job + badge shelf
- [ ] Streak computation on a daily schedule

## Phase 6 · Chat — ~2.5 weeks

- [ ] Room list, auto-provisioned class and division rooms
- [ ] Realtime message list with optimistic send
- [ ] Reply, edit, soft delete, reactions
- [ ] Image upload to the private bucket + signed URLs
- [ ] DMs via `open_dm`
- [ ] Announcement channels
- [ ] Moderation tools, report flow
- [ ] The privacy notice, on screen

Last on purpose: the most expensive feature with the strongest incumbent
(WhatsApp). See the honest risk assessment in `docs/06`.

## Phase 7 · Hardening & launch — ~1.5 weeks

- [ ] PWA manifest, icons, offline shell
- [ ] iOS install guidance (Web Push needs home-screen install — without this
      iPhone users silently receive nothing)
- [ ] Playwright e2e on the four critical journeys
- [ ] Rate limiting
- [ ] Accessibility pass: keyboard, screen reader, touch targets
- [ ] Load check with ~250 seeded students
- [ ] Onboarding and help screens
- [ ] Soft launch: one class, one semester

**Total: ~13–14 weeks part-time.** Realistically one semester.

## Suggested cut lines

If time runs short, cut in this order:

1. **Chat** (Phase 6) — WhatsApp already works. Keep announcement channels only.
2. **Portfolio + badges** (Phase 5) — lovely, not load-bearing.
3. **Org UI** (Phase 4) — the enforcement is in the database; roles can be
   assigned by SQL for one semester.

Phases 1–3 are not cuttable. Without them there is no product, only a schema.

## After v1

| Candidate | Trigger for building it |
|---|---|
| Telegram bot channel | Students ask for it; cheapest extra channel by far |
| Capacitor `.apk` | Someone wants a Play Store listing |
| Attendance | A dosen asks to use it |
| E2E encrypted DMs | You want a skripsi topic — this is a good one |
| Multi-jurusan | Another program asks |
| WhatsApp API | There is a budget |

## How to know it worked

Measure these at the end of one semester, honestly:

| Signal | Target |
|---|---|
| Students opening it ≥ 3×/week | > 60% of one class |
| Tasks entered within 24h of being announced | > 80% |
| Late submissions vs the previous semester | measurably fewer |
| Jadwal questions still asked in the WhatsApp group | approaching zero |

That last row is the real test. If people still ask *"besok kuliah jam berapa?"*
in WhatsApp, the app has not replaced the habit, whatever the usage numbers say.
