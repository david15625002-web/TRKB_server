# 08 · Design System

Working implementation: [`mockup/assets/css/tokens.css`](../mockup/assets/css/tokens.css)
and [`mockup/assets/css/app.css`](../mockup/assets/css/app.css).

## Direction

"Robotika style" here means **instrument panel**, not sci-fi decoration. The
reference points are robot teleoperation UIs, oscilloscope screens and PLC
diagnostic panels: dense data, monospace for anything numeric, thin precise
rules, and a single accent colour used sparingly so that when something *is*
accented it means something.

The discipline that keeps it from looking like a toy:

1. **Accent = state, not decoration.** The accent colour marks the live thing —
   the next class, an urgent deadline, the active tab. If everything glows,
   nothing reads as urgent.
2. **Monospace for data, sans for prose.** NIM, room codes, times, countdowns and
   class codes are monospace; names, descriptions and chat are sans. This is the
   single cheapest trick that makes an interface feel like instrumentation.
3. **Hairline borders over heavy shadows.** 1px rules at low opacity. Panels sit
   *in* the surface, not floating above it.
4. **Motion reports state changes.** A countdown ticks because time is passing; a
   status LED pulses because something is live. Nothing animates to be pretty.

## Four presets × two modes

You asked for all four looks, switchable per person. They are the same component
set with a different token layer — no component knows which theme is active.

| Preset | Character | Where it wins |
|---|---|---|
| `cyan_hud` | Near-black, cyan-teal accent, grid overlay, scanline | Default. Dense schedule screens, reads like control software |
| `amber_industrial` | Warm dark, amber accent, hazard striping | Workshop/lab feel; easier on eyes in a dark room |
| `campus` | Soft neutral, blue accent, rounder, more air | Daytime, projectors, showing a dosen |
| `blueprint` | Paper background, schematic blue, technical annotation | Distinctive; good for printing and portfolio screenshots |

Each ships light and dark. `theme_mode = 'system'` follows the OS.

Stored on `profiles.theme_preset` / `theme_mode` / `accent_override`, so the
choice follows the student to any device — not in `localStorage`.

### Switching mechanism

Two attributes on `<html>`, nothing more:

```html
<html data-theme="cyan_hud" data-mode="dark">
```

```css
:root[data-theme="amber_industrial"][data-mode="dark"] { --accent: #f59e0b; … }
```

No re-render, no flash, no JS beyond setting the attribute. The server renders
the correct attributes from the user's profile on first paint, so there is no
theme flicker on load.

## Tokens

Every colour is a variable. Components never contain a literal hex value.

```css
--bg            page background
--bg-elev       raised surface (header, nav)
--panel         card surface
--panel-2       nested surface
--border        hairline rule
--border-strong emphasised rule
--text          body text
--text-dim      secondary text
--text-faint    decorative / large-type only
--accent        the live state colour
--accent-fg     text on an accent fill
--ok --warn --danger
--grid          grid-overlay line colour
--radius --radius-sm --gap --shadow
--font-sans --font-mono
```

### Measured contrast

Computed, not estimated. Ratios against the surface the token is used on:

| Preset / mode | text/bg | text/panel | dim/panel | accent/panel | ok | warn | danger |
|---|---|---|---|---|---|---|---|
| cyan_hud / dark | 17.35 | 16.29 | 7.41 | 10.42 | 9.80 | 11.28 | 6.81 |
| cyan_hud / light | 16.30 | 17.72 | 6.26 | 5.36 | 5.48 | 4.92 | 6.47 |
| amber / dark | 17.07 | 16.05 | 6.95 | 8.75 | 6.09 | 11.26 | 5.00 |
| amber / light | 16.91 | 18.21 | 6.92 | 5.02 | 4.99 | 4.92 | 6.47 |
| campus / light | 16.78 | 17.85 | 7.53 | 5.17 | 3.77 | 3.19 | 4.83 |
| campus / dark | 16.00 | 14.48 | 7.00 | 6.74 | 8.91 | 10.26 | 6.19 |
| blueprint / light | 14.74 | 16.43 | 6.79 | 6.41 | 5.24 | 4.71 | 6.18 |
| blueprint / dark | 15.45 | 14.36 | 6.74 | 7.11 | 9.41 | 10.83 | 6.54 |

All body and secondary text clears **WCAG AA 4.5:1**; all status and accent
colours clear **3:1** for non-text and large-text use.

`--text-faint` ranges 3.75–4.76:1 and is therefore restricted to decorative use
and type ≥ 18px — it must never carry body copy. The constraint is written here
because it is the one a future contributor will otherwise break.

### Accent override

`profiles.accent_override` replaces `--accent` with a student's chosen hex. The
picker offers a curated set that is contrast-safe against every preset's panel
colour, because a free colour wheel will produce `#ffff00` on white within a day.

## Typography

| Use | Family | Size / weight |
|---|---|---|
| Body, names, chat | `Inter`, system sans | 15px / 400, 1.55 line-height |
| Data: NIM, times, rooms, countdowns, class codes | `JetBrains Mono`, `ui-monospace` | 13px / 500, `font-variant-numeric: tabular-nums` |
| Section labels | mono, uppercase | 11px / 600, `letter-spacing: .14em` |
| Headings | sans | 20–28px / 600, `letter-spacing: -0.01em` |

`tabular-nums` on every countdown and time is not a detail: without it the digits
change width as they tick and the whole row jitters.

## Layout

Mobile-first, because that is where the reads happen.

```
 < 640px   single column · bottom tab bar (5 items) · 16px gutters
 ≥ 640px   two columns where content allows
 ≥ 1024px  persistent left sidebar · wide schedule grid · 1280px max content
```

The timetable is the only genuinely hard responsive problem. A 7-day × 12-hour
grid cannot shrink to 360px honestly, so it changes form rather than scaling:

| Width | Schedule form |
|---|---|
| Phone | Vertical agenda list, one day at a time, swipe between days |
| Tablet | Horizontally scrollable 5-day grid with a sticky time column |
| Desktop | Full week grid |

Trying to render the same grid at every width is what makes most campus apps
unusable on a phone.

## Motion

| Element | Motion | Duration | Why |
|---|---|---|---|
| Page transition | fade + 4px rise | 180ms | Orientation |
| Panel mount | fade + 8px rise, 40ms stagger | 220ms | Suggests reading order |
| Status LED | opacity pulse | 2s loop | Something is live |
| Countdown | digit flip, 1s tick | — | Time is actually passing |
| Urgent deadline (< 6h) | border pulse on the accent | 1.6s loop | Earns attention |
| Scanline (HUD presets) | 8s vertical sweep, 3% opacity | 8s loop | Theme character, nearly subliminal |
| Grid overlay | static | — | Texture, never animated |
| Toast | slide from bottom | 240ms | Non-blocking |
| Tab switch | accent underline slides | 200ms | Continuity |

Easing is `cubic-bezier(.22,.61,.36,1)` for entrances and `linear` for anything
representing continuous time.

### Reduced motion is honoured properly

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: .01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: .01ms !important;
  }
}
```

Plus a `reduce_motion` flag on the profile, because some students want it off
while their OS setting stays on. The scanline and all looping pulses are
suppressed entirely — not merely shortened, since an infinite loop shortened to
0.01ms is a strobe.

## Components

Primitives (theme-agnostic, no literal colours):

```
Panel          bordered surface, optional mono label in the top rule
StatusLED      ●  ok / warn / danger / idle, optional pulse
Countdown      mono, tabular, ticks live, switches to danger under 6h
Chip           skill tag, role badge, subject pill
DataRow        label left (mono, dim) · value right (mono, bright)
SectionLabel   uppercase mono rule
Avatar         image, initials fallback, optional role ring
EmptyState     icon + one line + one action
ThemePicker    4 preset swatches × mode toggle × accent row
```

Feature components:

```
ScheduleGrid / AgendaList     TaskCard        TaskComposer
OrgTree                       RoleBadge       ApprovalQueue
RoomList / MessageList        MessageComposer
ProfileHeader                 SkillCloud      ProjectCard
BadgeShelf                    StreakMeter     NotifPrefsForm
```

## Iconography

One stroke-icon set (Lucide), 1.5px stroke, 20px default, `currentColor` only —
never a hardcoded colour, or icons break under theme switching.

## Accessibility checklist

- [x] 4.5:1 on all body and secondary text, every preset and mode (measured above)
- [x] `prefers-reduced-motion` respected, loops suppressed not shortened
- [x] Focus ring: 2px accent + 2px offset, never removed
- [ ] Keyboard navigable throughout — Phase 1
- [ ] Screen-reader labels on every icon-only control — Phase 1
- [ ] Status never conveyed by colour alone (LEDs carry a text label too) — partial in mockup
- [ ] 44×44px minimum touch targets — Phase 1
- [ ] Indonesian `lang` attribute, switching with locale — Phase 1

Unchecked items are honest: they are Phase 1 implementation work, not claims
about the mockup.
