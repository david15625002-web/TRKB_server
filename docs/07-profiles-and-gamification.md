# 07 · Profiles, Portfolio & Gamification

Feature 4: *"make custom profile for each person, can make it into personalised."*
Four layers, increasing in cost to build and in value to the program.

## Layer 1 · Identity and personalisation

| Field | Notes |
|---|---|
| `avatar_url`, `banner_url` | Public storage bucket, owner-write |
| `display_name` | What appears in chat; `full_name` stays for official lists |
| `pronouns` | Free text, self-declared, **never inferred from the name**, never required |
| `headline` | One line under the name — *"Suka bikin robot line follower"* |
| `bio` | ≤ 500 chars |
| `links` | `jsonb` array of `{label, url}` — GitHub, LinkedIn, Instagram |
| `accent`, `theme_mode` | One of six accent colours, plus light/dark/system. Stored **server-side**, so the look follows you to any device |
| `locale` | `id` / `en` |
| `reduce_motion` | Respects the OS setting but can be forced on |

Theme choice living in the database rather than `localStorage` is a small thing
that reads as care: sign in on a lab PC and it is still *your* app.

## Layer 2 · Skills

`skills` is a **curated** list; `user_skills` links a person to a skill with a
coarse level.

```
level 1 = belajar    level 2 = bisa    level 3 = mahir
```

Three levels on purpose. A 1–10 scale invites inflation and conveys nothing — the
only question anyone actually asks is *"can I ask this person for help?"*

Curation is the important design choice. Free-text tags produce `Arduino`,
`arduino`, `Arduino Uno`, `ARDUINO`, `arduino uno r3` and the directory becomes
useless. A holder of `skill.manage` approves suggestions.

Seeded with 30 skills across six categories genuinely relevant to a robotics
program: `embedded` (Arduino, ESP32, STM32, Raspberry Pi, Embedded C, PLC),
`electronics` (PCB, soldering, power electronics, sensor fusion), `mechanical`
(SolidWorks, Fusion 360, 3D printing, machining, kinematics), `software`
(ROS 2, Python, C++, TypeScript), `ai` (PyTorch, TensorFlow, OpenCV, YOLO, RL,
PID, SLAM), `tooling` (Git, Linux, Docker, MATLAB).

**Why this earns its place:** *"siapa yang bisa PCB?"* becomes a query instead of
a question in a group chat nobody answers. For a program where every lomba needs
a mixed team, that is the single most useful social feature here.

## Layer 3 · Portfolio

```
projects
  title, summary, description, cover_url, gallery[]
  repo_url, demo_url, video_url
  context        'Lomba KRI 2026' | 'Tugas Besar Mikrokontroler'
  subject_id     optional link to the course
  year, tags[]
  is_public, is_pinned, sort_order

project_collaborators (project_id, user_id, role)
```

`project_collaborators` matters: robot projects are team projects, and a
portfolio that lets one person claim a group build is both inaccurate and
socially corrosive.

This is the strongest thing to show a dosen. A program-wide, browsable record of
what students actually built — searchable by skill and subject — is the kind of
artefact that gets an app adopted officially rather than tolerated.

It is also the largest feature area in this layer, which is why `docs/10` puts it
in Phase 5, after the things that make the app useful on a Tuesday morning.

## Layer 4 · Gamification

You asked for badges, streaks and contribution stats. They exist, with one
deliberate constraint.

### What is measured

```sql
user_stats
  tasks_completed, tasks_on_time, tasks_late
  streak_current, streak_best, streak_updated_on
  messages_sent, helpful_reactions
```

**Streak** = consecutive calendar days (WIB) with at least one on-time
submission. Recomputed from `task_submissions` by `recompute_user_stats()` rather
than incremented in place — a hand-incremented counter drifts the first time a
transaction rolls back, and then nobody trusts the number.

### Badges

`rule` is machine-readable JSON, so a new badge is an `INSERT`, not a deploy:

| Badge | Tier | Rule |
|---|---|---|
| Langkah Pertama | bronze | first task completed |
| Tepat Waktu | bronze | 10 on-time |
| Disiplin | silver | 50 on-time |
| Runtun 7 Hari | bronze | 7-day streak |
| Runtun 30 Hari | gold | 30-day streak |
| Semester Bersih | gold | a full term with zero late |
| Perakit | bronze | first public project |
| Insinyur | silver | 5 public projects |
| Serba Bisa | silver | skills in 4 categories |
| Pengurus | special | held a kepengurusan role |
| Juru Catat | special | entered 25 tasks/schedules for the class |

Badges are awarded **server-side only**. There is no client INSERT policy on
`user_badges`, so a student cannot grant themselves one.

### The constraint, and why

**There is no badge for chat volume, and no public leaderboard.**

- Rewarding message count produces noise, not help. The person who posts 400
  messages is not the person who answered the question.
- A public ranking of who submits work on time turns a coordination tool into a
  public shaming board. In a cohort of 40 people who see each other every day,
  that is a real social cost for a cosmetic feature. *Your own* streak is
  motivating; a ranked list of everyone's is not.

`Juru Catat` is the deliberate exception that rewards *contribution* rather than
activity: the sekretaris who keeps the jadwal accurate is doing the work that
makes the app function, and that should be visible.

### Progress visibility for pengurus

Ketua Kelas holds `task.view_progress` — they can see **who has handed in**, in
order to chase people. They cannot change anyone's status:

```sql
-- read-only for pengurus
create policy task_submissions_read_by_pengurus on task_submissions
  for select using (...)

-- write only for the owner
create policy task_submissions_own on task_submissions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
```

This was asked about during planning as a possible escalation ("report who hasn't
submitted to the ketua"). The resolution: the ketua can *look*, because that is
their job, and the app does not *push* a shame list to them unprompted.
