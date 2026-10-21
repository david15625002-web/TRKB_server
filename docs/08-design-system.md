# 08 · Design System

**Source: the Duolingo package from [`nexu-io/open-design`](https://github.com/nexu-io/open-design)**
(`design-systems/duolingo/` — `DESIGN.md` + `tokens.css`).

Implementation: [`mockup/assets/css/tokens.css`](../mockup/assets/css/tokens.css)
and [`mockup/assets/css/app.css`](../mockup/assets/css/app.css).

## Why this one

Two earlier directions were tried and rejected: a dark instrument-panel HUD
(coherent but stiff) and a soft tonal Material/Fluent system (friendlier but
still generic). Both were my own interpretation rather than a real system.

Duolingo was chosen from a 152-package catalog because **the app already has
its subject matter**. Streaks, badges, on-time counters and a daily habit loop
are exactly what that design language was built to express — so the streak
strip and the badge shelf look native here instead of bolted on.

## What is taken verbatim

| | Value |
|---|---|
| Owl Green | `#58cc02` · deep `#46a302` · light `#89e219` |
| Eel Blue | `#1cb0f6` |
| Streak Orange | `#ff9600` · Bee Yellow `#ffc800` · Gem Pink `#ce82ff` |
| Cardinal Red | `#ff4b4b` |
| Shadow | `0 4px 0` — hard, no blur, the "tactile press" signature |
| Borders | **2px, never hairlines** |
| Radii | 12px buttons · 16px cards · 20px sheets · pill chips |
| Easing | `cubic-bezier(.34, 1.56, .64, 1)` — back-out overshoot |
| Type scale | 12 / 13 / 15 / 18 / 24 / 32 / 40 / 56 |

The signature is the shadow. A button sits on a 4px hard edge and collapses to
`0 0 0` on `:active`, so it physically depresses under the finger. That one
detail does more for the "fun" brief than any amount of colour.

## Four deliberate departures

### 1 · Text on a bright fill is dark, not white

Duolingo's own pairing puts white on `#58cc02`. Measured:

| Pairing | Ratio | |
|---|---|---|
| white on Owl Green | **2.09:1** | fails WCAG AA badly |
| white on Eel Blue | **2.44:1** | fails |
| white on Streak Orange | **2.18:1** | fails |
| dark ink on Owl Green | **7.86:1** | passes |
| dark ink on Eel Blue | **6.72:1** | passes |
| dark ink on Streak Orange | **7.52:1** | passes |

The bright fill is the whole point of the system, so the fill is kept and the
ink is changed. `--accent-ink` is the accent darkened until it clears 4.5:1 on
its own fill.

### 2 · An accent used as *text* is a darker variant

Raw Owl Green on white is 1.9:1 — unreadable as a label. `--accent-text` is
darkened until it clears 4.5:1 on the canvas:

| Accent | On white | On the dark canvas |
|---|---|---|
| Green | `#3a8701` → 4.52 | `#58cc02` → 8.05 |
| Blue | `#147daf` → 4.58 | `#1cb0f6` → 6.88 |
| Orange | `#ab6400` → 4.61 | `#ff9600` → 7.70 |

On the dark canvas the raw brand colour already clears comfortably, so it is
used directly.

### 3 · A dark mode was added

The source package is white-canvas only. These surfaces follow Duolingo's own
app dark theme (deep teal-navy `#131f24`), and keep the 2px borders and the 4px
shadow — losing those would lose the system.

| | Light | Dark |
|---|---|---|
| Canvas | `#ffffff` | `#131f24` |
| Surface | `#f7f7f7` | `#1f2f35` |
| Text | `#3c3c3c` (11.03:1) | `#f1f7fb` (15.56:1) |
| Secondary | `#6b6b6b` (5.33:1) | `#a9bcc4` (8.55:1) |
| Border | `#e5e5e5` | `#37464f` |

### 4 · Secondary text was retuned

The source's `#777777` measures 4.48:1 on white — three hundredths short of AA.
Moved to `#6b6b6b` (5.33:1).

## Three accents

Picked per person in **Pengaturan**, alongside light / dark / system.

```html
<html data-accent="green" data-mode="light">
```

All three are brand colours from the source package rather than invented hues:
Owl Green is the primary, Eel Blue is its hint/info colour, Streak Orange is the
streak counter. Six combinations total, every one verified distinct and legible.

## Typography

| Role | Face | Note |
|---|---|---|
| Display | **Fredoka** 500–700 | Feather Bold is proprietary; Fredoka is the closest rounded face on Google Fonts |
| Body | **Nunito** 600–800 | Stands in for Mona Sans. Body weight is **600**, not 400 — the system runs heavy and 400 reads thin |
| Data | **DM Mono** | Times, countdowns, NIM only |

Labels and buttons are uppercase with light tracking, which is the source's
chrome convention. This is the one place uppercase earns its keep — on short
action words, not on paragraph labels.

## Layout

```
 < 640px   single column · bottom nav with a bordered pill · FAB
 ≥ 820px   two columns where content allows
 ≥ 1024px  navigation rail · full week grid · 1080px max (source container-max)
```

## Motion

| Element | Motion |
|---|---|
| Button / FAB press | translateY(4–5px), shadow collapses to 0 |
| Checkbox | fill + `scale(1.1) rotate(-6deg)` |
| Card mount | rise 12px + `scale(.985)`, overshoot easing |
| Day selector | lifts 2px and takes the accent fill |
| Badge hover | lift 4px + `rotate(-2deg)` |
| Live dot | pulse `scale(.6)` |

Reduced motion is honoured via `prefers-reduced-motion` and a manual toggle;
loops are suppressed entirely rather than shortened.


## Density tiers

The Duolingo language is loud by design, and that is right for the screens you
open to *feel* something. On the screens you open to *read* dense information —
a week of timetable, an org chart, a message list — the same 4px shadows and
2px borders compete with the content.

So the system speaks at two volumes. `calm` keeps every colour, radius and
motion curve; it only reduces physical weight.

| | full | calm |
|---|---|---|
| Border | 2px | 1.5px |
| Card shadow | `0 3px 0` | `0 1px 0` |
| Button shadow | `0 4px 0` | `0 2px 0` |
| Card radius | 16px | 14px |
| Chips & buttons | uppercase, tracked | sentence case |
| Row hover | lifts | tints only |

| Screen | Tier | Why |
|---|---|---|
| Beranda, Tugas, Profil, Pengaturan | **full** | the habit loop — streaks, XP, completion |
| Jadwal, Organisasi, Obrolan, Notifikasi | **calm** | read-heavy, scanned rather than felt |

Set per screen as `data-density` on `<html>`. This is one system at two
volumes, not two designs: a student moving between tabs should feel a change
in *pace*, not in product.

## Robi

The source package calls for "mascot-as-character, not a static logo". A
robotics program has the obvious character to cast.

Robi is inline SVG whose body is `var(--accent)`, so it changes colour with the
student's choice — verified in the test suite, not assumed. Four moods:

| Mood | Where | Motion |
|---|---|---|
| `idle` | dashboard greeting | slow float, blink every ~4s |
| `happy` | profile, cleared task lists | hop with a slight rotation, bulb pulses |
| `sleep` | empty states | gentle breathing |

What Robi says is **derived from the screen**, never random: overdue tasks
first, then tasks due today, then an imminent class, then the streak. A mascot
that says something untrue is worse than no mascot.

## XP and levels

```
10 XP per task · +5 on time · 50 XP per level
```

XP is **derived from the stats**, never incremented in place — the same
reasoning as the streak being recomputed in SQL. A hand-counted total drifts
after one rollback, and then nobody trusts the number.

- Level ring in the top bar, on every screen
- Large ring on the profile, with progress into the next level
- `+15 XP` rises from the checkbox you actually pressed
- Confetti bursts from that same point
- A combo counter appears when a second task is completed within 4 seconds
- Crossing a level threshold changes the toast to a level-up

**Every celebration is suppressed entirely under reduced motion** — not
shortened. A confetti burst compressed to 0.01ms is a flash, which is the
opposite of accessible. Verified in the suite: with motion reduced, zero
confetti nodes and zero XP pops are created.

Confetti also removes itself; the suite asserts the DOM returns to zero
`.confetti` nodes after the animation, because a leak here would accumulate
on every completion for the whole session.

## Accessibility

- [x] Accent ink on fills ≥ 4.5:1, all three accents (table above)
- [x] Accent-as-text ≥ 4.5:1, both modes
- [x] Body text 11.03:1 light, 15.56:1 dark; secondary 5.33 / 8.55
- [x] Six accent × mode combinations verified distinct
- [x] No horizontal page scroll at 1280 / 390 / 320px on all 8 screens
- [x] Status carries a text label, not colour alone
- [x] `prefers-reduced-motion` honoured
- [x] Celebrations suppressed, not shortened, under reduced motion
- [x] The mascot carries a real `aria-label`, and never conveys information the text does not
- [ ] Full keyboard navigation — Phase 1
- [ ] Screen-reader labels on icon-only controls — Phase 1
- [ ] An `aria-live` announcement on XP and level change — Phase 1 (the visual
      celebration currently has no screen-reader equivalent)

Note that the chunky-shadow press depends on `:active`, which has no keyboard
equivalent — Phase 1 must add a `:focus-visible` treatment that reads as
clearly as the press does.

## Verification

`mockup/tests/check.mjs` drives the prototype in Chromium and asserts all 8
screens render, the countdown ticks, interactions change state, all 6 accent ×
mode combinations produce distinct palettes, `system` resolves to a concrete
mode, each screen lands in its intended density tier, the calm tier is
measurably thinner than full, XP rises on completion and stays inside its
level, confetti cleans itself up, the mascot renders and follows the accent,
celebrations are suppressed under reduced motion, and no screen leaks
horizontal page scroll at 390px or 320px.

Both suites now run in CI on every push and pull request
(`.github/workflows/checks.yml`). That matters most for the database job:
authorisation lives in RLS policies, and a weakened policy fails silently —
the app simply starts permitting something it should not.

Bugs it has caught across the three design iterations: 306px and 29px of
overflow on jadwal and obrolan, a tab bar visible on desktop, a 10px/50px
overflow on settings, an invisible accent selection ring, grid children
stretching to dead space, and a 6px overflow on the org rows at 320px.
