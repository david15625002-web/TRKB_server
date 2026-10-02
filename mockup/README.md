# Mockup · clickable prototype

No build step, no dependencies, no network calls except the two Google Fonts.

```bash
xdg-open mockup/index.html            # or just double-click it
python3 -m http.server 8080 --directory mockup
```

## What is real here

| Works | Notes |
|---|---|
| 12 palettes | 6 accent colours × light/dark, switched live in **Pengaturan**; `system` follows the device |
| Navigation | 8 screens, sidebar on desktop, bottom tab bar on phone |
| Live countdown | Ticks to the next class, computed from the sample jadwal |
| Task completion | Tick a task, state updates, toast fires, counters recalculate |
| Member approval | Approve/reject a pending student, row disappears, toast fires |
| Chat | Switch rooms, send a message, it appears in the thread |
| Day switching | Jadwal day strip filters the agenda |
| Week grid | Horizontally scrollable timetable |
| Modals | Add-task and add-schedule forms, with the real reminder/clash copy |
| Notification previews | Four buttons in Pengaturan fire the exact H-1, H-3h, class and cancellation copy |
| Reduced motion | Honours `prefers-reduced-motion`, plus a manual toggle |

## What is not real

- **No backend.** State lives in memory and resets on reload.
- **No authentication.** You are always the Ketua Kelas of `TRKB-1 25`.
- **No validation.** Forms accept anything and only show the intended copy.
- Buttons marked with a "Prototipe" toast are flows that are designed in
  `docs/` but not wired up here.

## Screens

| Screen | Shows |
|---|---|
| **Beranda** | Next-class countdown, 4 metrics, today's jadwal, nearest deadlines, approval queue |
| **Jadwal** | Day strip, agenda, scrollable week grid, CSV import panel |
| **Tugas** | Active vs done, urgency states, and the generated reminder schedule for the nearest task |
| **Organisasi** | BPH tree, divisions, classes with derived semesters, permission-scope demonstration |
| **Obrolan** | Room list, class/announcement/division/public/DM, privacy notice on DMs |
| **Profil** | Banner, stats, badge shelf, skill cloud, portfolio |
| **Pengaturan** | Theme picker, reminder preferences, notification previews |
| **Notifikasi** | Inbox with read/unread state |

## Files

```
index.html              shell, topbar, nav containers
assets/css/tokens.css   6 accent seeds x 2 modes — every colour lives here
assets/css/app.css      components; contains no literal colours
assets/js/data.js       sample data, mirroring db/seed.sql
assets/js/app.js        views and interaction
```

The split matters: `app.css` referencing only tokens is what makes twelve
palettes work from one stylesheet. If you add a component, keep that rule — a
literal hex in `app.css` will look wrong in at least half of the twelve
combinations.
