# 11 · Open Questions

Decisions still outstanding. Each says what is blocked by it and what happens if
nobody decides — because an undecided question with a stated default is not a
blocker, it is a deadline.

## Needs your answer

### 1 · Real dosen and subject data

`db/seed.sql` ships placeholders (`Dosen Pengampu Satu`, a plausible but invented
curriculum). The real list must replace them before launch.

- **Blocks:** nothing structural; it is data entry.
- **Question:** is there an official TRKB curriculum list (subject codes, SKS,
  which semester) you can export, or does this get typed by hand?
- **Default if undecided:** the Sekretaris types them in during Phase 2.

### 2 · Who is Super Admin after you graduate?

The system assumes one or two Super Admins. You will leave.

- **Blocks:** the long-term survival of the project, nothing in the code.
- **Options:** (a) hand over to the next Ketua HIMA each periode — simple but
  concentrates power in someone who may not be technical; (b) a dosen holds it —
  stable but needs their buy-in; (c) two Super Admins, one pengurus and one
  dosen.
- **Default if undecided:** (a), with the audit log as the safety net.

### 3 · License

Nothing chosen yet.

- **MIT** — maximum reuse; another campus could fork it, which is arguably the
  best outcome for a student project.
- **AGPL-3.0** — forces anyone running a modified version to publish changes.
- **Proprietary** — if HIMA or the program wants to own it outright.
- **Default if undecided:** MIT, and add a `LICENSE` file in Phase 1.

### 4 · Hosting account ownership

Vercel and Supabase projects must live in an account that outlives you.

- **Question:** your personal account, a shared HIMA account, or a campus one?
- **Risk if undecided:** the app dies when you lose access to your student email.
- **Default:** create a dedicated `trkb.dev@…` account early and share the
  credentials with one other pengurus.

### 5 · Does the Ketua see who has *not* submitted?

Currently: yes, read-only (`task.view_progress`), and the app does not push an
unsubmitted list to them unprompted.

- **Question:** is even that too much? It is socially sensitive in a cohort of 40
  people who see each other daily.
- **Alternative:** show only a count ("28 dari 38 sudah mengumpulkan") and no
  names.
- **Default:** keep as designed, revisit after one semester of real use.

## Technical, decidable later

### 6 · Should a completed task still push its reminder?

Today it does — the reminder is driven by the deadline, not by a self-reported
checkbox.

- **For suppressing:** fewer useless notifications; respects the student who is
  organised.
- **Against:** a student who mis-taps "done" loses their only warning.
- **Lean:** suppress the H-3h reminder when done, keep the H-1. Decide with real
  usage data in Phase 3.

### 7 · Students repeating a semester

`semester_of()` derives the semester from angkatan, so a student repeating a year
is shown their angkatan's semester, not their actual one.

- **Fix when needed:** a nullable `semester_override` on `profiles`.
- **Why not now:** it adds a field that is almost always null, for a case that
  may not arise in the first year.

### 8 · Multiple classes per student

The model allows it (`memberships` is many-to-many), but the UI assumes one
primary class. Students taking a repeat subject with another class would need
better handling.

- **Default:** `primary_class_id` drives the dashboard; extra memberships still
  grant chat and schedule access. Revisit if it actually happens.

### 9 · Attachment storage budget

Supabase free tier gives 1 GB. Chat images plus task attachments will reach that.

- **Mitigations:** client-side compression before upload, 90-day retention on
  chat images, 2 MB per-file cap.
- **Decide by:** Phase 6, when chat images become real.

### 10 · Offline support depth

The PWA shell caches, but how much data?

- **Minimum:** today's jadwal and open tasks cached, read-only offline.
- **Maximum:** full offline with a sync queue — significantly more work and a
  conflict-resolution problem.
- **Lean:** minimum. Campus WiFi is unreliable but not absent.

## Deliberately deferred

| Question | Revisit when |
|---|---|
| E2E encrypted DMs | Someone wants a skripsi topic (`docs/06`) |
| WhatsApp channel | There is a budget for the Business API (`docs/05`) |
| Attendance | A dosen asks for it (`docs/01`) |
| Grades | Probably never — leave it to the campus system |
| Kas / payments | Never; money in a student app invites disputes |
| Multi-jurusan tenancy | Another program asks to use it |

## Answered during planning

Recorded so they are not reopened:

| Question | Decision |
|---|---|
| Platform | PWA first (Next.js), Capacitor `.apk` later if wanted |
| Backend | Supabase — Postgres + Auth + Realtime + Storage |
| Notification channels | In-app + Web Push + email (digest) |
| Scope | Whole TRKB program, not one class, not the whole campus |
| Schedule source | Manual entry + CSV/Excel import. **No portal scraping.** |
| Role model | Full scoped hierarchy; HIMA structure editable by Super Admin |
| Class identity | `TRKB-1 25` = TRKB, kelas 1, angkatan 2025 |
| Semester | Derived from angkatan + current term, never stored |
| Chat | Rooms + DMs, text and images, no E2E in v1, admin access stated plainly |
| Profiles | Identity + skills + portfolio + gamification, all four layers |
| Appearance | Soft tonal direction; 6 accent colours × light/dark/system, chosen per person |
| Dosen | Data only, no accounts |
| Registration | Campus email + NIM, approved by Ketua/Sekretaris Kelas |
| Reminders | H-1 at 18:00 + H-3h, user-overridable, quiet hours defer |
| Language | Bahasa Indonesia default, English toggle |
