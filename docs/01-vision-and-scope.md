# 01 · Vision & Scope

## The problem, stated honestly

Class coordination in the TRKB program currently lives in WhatsApp groups. That
fails in four specific, repeatable ways:

| Failure | What actually happens |
|---------|----------------------|
| **Information decay** | A tugas announced on Tuesday is buried under 200 messages by Thursday. The deadline passes. |
| **No single source of truth** | Three people hold three different versions of the jadwal after a room change. |
| **Handover amnesia** | Each new kepengurusan starts from zero. Last year's files are in someone's personal Google Drive. |
| **No proactive reminders** | WhatsApp notifies you when a message is *sent*, never when a deadline is *near*. |

The last row is the core insight: **chat apps are push-on-event, but coursework
needs push-on-time.** Nothing in a WhatsApp group can wake a student up the day
before a deadline. That is the gap this system fills, and every other feature
exists to make that one work.

## Users

| Persona | Count (est.) | Primary need | Frequency |
|---------|--------------|--------------|-----------|
| **Anggota** (regular student) | ~200+ | "What do I have tomorrow, and what's due?" | Daily, 30 seconds |
| **Sekretaris Kelas** | 1 per class | Input jadwal once per semester, input tugas as they're announced | Weekly, a few minutes |
| **Ketua Kelas** | 1 per class | Approve new members, broadcast urgent info, chase submissions | Weekly |
| **Pengurus HIMA** (Ketua, Wakil, Sekretaris, Bendahara, Kadiv) | ~15 | Program-wide announcements, division coordination | Weekly |
| **Super Admin** | 1–2 | Manage academic terms, org structure, role definitions | Per semester |
| **Dosen** | n/a | — *not users in v1.* Represented as data only. | — |

The deliberate decision not to give dosen accounts removes the single biggest
adoption risk: this system is useful on day one even if **zero** lecturers ever
hear about it.

## Scope of v1

### In scope

- **Schedule.** Recurring rules per class per academic term → generated sessions.
  Per-session override for room change, kuliah pengganti, and cancellation.
- **Tasks.** Created by Ketua/Sekretaris Kelas, attributed to a subject and dosen.
  Personal done-tracking per student (your checkbox is yours).
- **Reminders.** H-1 at 18:00 WIB + H-3 hours for tasks; 30 min before class.
  Per-user overrides, per-subject mute, quiet hours. Three channels:
  in-app, Web Push, email.
- **Roles.** Scope-bound memberships with validity periods. HIMA structure and
  role definitions editable by Super Admin — nothing hardcoded.
- **Registration.** Campus email + NIM + class selection → pending → approved by
  that class's Ketua or Sekretaris.
- **Profiles.** Avatar, banner, display name, pronouns, bio, theme preference,
  robotics skill tags, pinned projects, badges, streaks.
- **Chat.** Auto-provisioned class and division rooms, program announcement
  channel, opt-in public rooms, 1-to-1 DMs. Text + images. Reply, edit, delete,
  reactions, read state.
- **Theming.** 4 presets × light/dark, chosen per person, persisted server-side
  so it follows you across devices.
- **i18n.** Bahasa Indonesia default, English toggle.

### Explicitly out of scope for v1

Writing these down matters as much as the in-scope list — it's what stops the
project from never shipping.

| Not building | Why | Revisit? |
|--------------|-----|----------|
| Scraping the UNIKOM academic portal | Fragile, needs credentials we must never store, possible policy violation | Only with written permission + an official API |
| WhatsApp notifications | Official API costs money; unofficial libraries get numbers banned | Yes — the channel adapter is designed for it (see `05`) |
| End-to-end encrypted DMs | Key management + device recovery is a project of its own | Good skripsi topic for v2 |
| Attendance / absensi | Needs either dosen buy-in or location trust; both are hard | v2, after adoption |
| Grades / nilai | Sensitive academic record. Wrong data here is a real problem for a real student | Probably never — leave it to the campus system |
| Voice notes & file sharing | Storage cost + abuse moderation | v1.1, low effort once chat exists |
| Dosen accounts | Adoption dependency we don't need | When a lecturer asks for it |
| Native iOS build | PWA covers it; Apple Developer account costs $99/yr | When there's budget |
| Payments / kas kelas | Money in a student app invites disputes and liability | No |

## Constraints we're designing against

1. **Zero budget.** Supabase free tier, Vercel hobby tier, free email tier. The
   schema and query patterns must stay inside those limits — see `02`.
2. **Phones, not laptops.** Most reads happen on a mid-range Android phone on
   campus WiFi. Mobile-first layout, small payloads, optimistic UI.
3. **One student maintainer.** You. Every feature must be debuggable alone at
   23:00 the night before a demo. This is why we prefer boring Postgres over
   clever distributed anything.
4. **Hostile data entry.** The person typing the jadwal is tired and on a phone.
   CSV import, sane defaults, and forgiving validation are not polish — they're
   load-bearing.
5. **Trust is social, not technical.** Everyone in a class knows each other.
   The threat model is accidental damage and outsiders, not sophisticated
   attackers. Design for *blast-radius containment*, not for nation-states.

## What "done" looks like for v1

A second-semester student who installed the PWA once:

1. Opens it at 07:00, sees today's two classes with room numbers and a
   countdown to the next one.
2. Got a phone notification at 18:00 yesterday: *"Besok: Laporan Praktikum
   Mikrokontroler — dikumpulkan 23:59."*
3. Taps the task, marks it done, and the streak counter ticks up.
4. Never once opened the WhatsApp group to find out what was due.

If that loop works for 30 students for one full semester, v1 succeeded.

## Non-goals as a cultural statement

This is a tool for a program, not a startup. There is no growth target, no
engagement metric to maximise, and no reason to add a feed. If a feature doesn't
help someone get to class on time or hand work in, it doesn't belong here.
