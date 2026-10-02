# 08 · Design System

Working implementation: [`mockup/assets/css/tokens.css`](../mockup/assets/css/tokens.css)
and [`mockup/assets/css/app.css`](../mockup/assets/css/app.css).

## Direction: soft tonal

Influenced by Material 3 and Fluent: surfaces separated by **tone**, generous
rounding, soft elevation, and one accent colour the student picks for
themselves.

> **This replaced an earlier direction.** The first version was an instrument
> panel — hairline borders on near-black, uppercase monospace labels, HUD
> scanlines. It was coherent, and it was *stiff*. Four specific things caused
> that, and they are worth naming so they do not creep back:
>
> | Stiff | Now |
> |---|---|
> | Every label uppercase monospace with wide letter-spacing | Labels are ordinary sentence-case text |
> | 1px borders separating every surface | Surfaces separated by tone; borders are rare |
> | Small radii (3–14px), square blueprint corners | 12–28px, pill-shaped controls |
> | Four fixed theme presets to choose between | One warm system, six accent colours |

The four rules that hold it together:

1. **Tone, not borders.** A card is a lighter or darker surface than its parent.
   Reaching for a border is usually a sign the tone step is too small.
2. **Rounding is consistent and generous.** Controls are pills; cards are 24px.
   Mixing radii is what makes an interface look assembled from parts.
3. **One accent, used for state.** The accent marks the live thing — next class,
   active tab, primary action. Status colours (success, warning, danger) are a
   separate system and never double as the accent.
4. **Motion overshoots slightly.** Buttons scale to 0.97 on press; the day
   selector lifts; the FAB pops in. A spring curve on small interactions is
   most of what reads as "fun" without adding any decoration.

## Accent seeds

The student picks one of six. Every token follows.

```html
<html data-seed="indigo" data-mode="light">
```

Values were **derived numerically, not picked by eye** — each seed was darkened
toward black (light mode) or lightened toward white (dark mode) until it met a
threshold:

| Seed | Light accent | vs surface | white on it | Dark accent | vs surface |
|---|---|---|---|---|---|
| Indigo | `#5b5bd6` | 5.25 | 5.37 | `#8b8be2` | 6.07 |
| Blue | `#1971e3` | 4.55 | 4.65 | `#5195ee` | 6.07 |
| Green | `#1c853a` | 4.60 | 4.70 | `#4ba565` | 6.06 |
| Amber | `#ba5a08` | 4.51 | 4.61 | `#e8720c` | 6.03 |
| Pink | `#ce3a75` | 4.58 | 4.68 | `#e26c9b` | 6.04 |
| Teal | `#008476` | 4.50 | 4.60 | `#38a398` | 6.05 |

Every accent clears **4.5:1** as text on its own surface and as button text in
light mode, and **6:1** in dark mode. Neutrals clear comfortably: body text
16.77:1 light and 14.46:1 dark; secondary text 8.58:1 and 10.77:1.

This matters because an accent colour is a *user* choice. A picker that lets
someone select an unreadable combination is a bug, not a feature — so the picker
only offers values that were checked first.

## Tokens

```css
--surface  --surface-dim  --surface-container  --surface-high  --surface-card
--on-surface  --on-surface-variant  --outline
--primary  --on-primary  --primary-container  --on-primary-container
--success --warning --danger --info   (each with a -bg companion)
--subj-1 … --subj-6                   (subject identity, dots and rails only)
--e1 --e2 --e3                        (elevation)
--r-xs … --r-full                     (shape)
--sp-1 … --sp-8                       (spacing)
--font-display --font-sans --font-mono
--ease --ease-bounce --dur-fast --dur --dur-slow
```

`app.css` contains **no literal colour**. That constraint is what lets twelve
palettes work from one stylesheet; a hex value in a component rule will look
wrong in at least half of them.

## Typography

| Role | Face | Use |
|---|---|---|
| Display | **Outfit** 500–700 | Headings, metric numbers, brand, avatars |
| UI | **Plus Jakarta Sans** 400–700 | Everything read as language |
| Data | **DM Mono** 400–500 | Times, countdowns, NIM — nothing else |

Outfit is geometric and slightly rounded, which carries the friendliness without
a novelty face. Plus Jakarta Sans is warm and holds up at 12–13px on a phone.
Monospace is now confined to digits that must align; the old design used it for
labels, which is precisely what made it feel like a readout.

`font-variant-numeric: tabular-nums` on every countdown and statistic. Without
it the digits change width as they tick and the row jitters.

## Layout

```
 < 640px   single column · bottom navigation with a pill indicator · FAB
 ≥ 820px   two columns where content allows
 ≥ 1024px  persistent navigation rail · full week grid · 1240px max
```

The timetable still changes form rather than scaling — agenda on a phone,
scrollable grid on a tablet, full week on desktop. A 7×12 grid cannot shrink to
360px honestly.

Grid children use `align-items: start` so a short panel does not stretch to its
neighbour's height, and every flex or grid child that holds text carries
`min-width: 0`.

## Motion

| Element | Motion | Duration |
|---|---|---|
| Panel mount | fade + 10px rise, 40ms stagger | 380ms |
| Button press | scale 0.97 | 120ms |
| FAB entry | scale 0.8 → 1 with overshoot | 380ms |
| Day selector | lift 2px + elevation on select | 220ms |
| Checkbox | fill + scale 1.06 | 220ms bounce |
| Live dot | opacity + scale breathe | 2.4s loop |
| Toast | rise 18px + scale 0.96 | 380ms bounce |
| Bottom sheet | rise 26px | 380ms |

Easing is `cubic-bezier(.2,0,0,1)` for entrances and
`cubic-bezier(.34,1.4,.64,1)` where a small overshoot helps.

Reduced motion is honoured through both `prefers-reduced-motion` and a manual
toggle, since some students want it off while their OS setting stays on.
Looping animations are suppressed entirely rather than shortened — an infinite
loop compressed to 0.01ms is a strobe.

## Components

```
Panel · Chip · StatusDot · Countdown · DataRow · Avatar · Bar · EmptyState
Button (filled / tonal / ghost) · FAB · Segmented · SeedPicker · Switch row
NavRail · BottomNav · BottomSheet · Toast
ScheduleSlot · WeekGrid · DayStrip · TaskCard · OrgNode
RoomList · MessageBubble · Composer · BadgeShelf · SkillCloud · ProjectCard
```

Each schedule subject keeps the same `--subj-*` colour everywhere, so a week
reads by colour before it is read by text.

## Accessibility

- [x] Accent seeds verified ≥ 4.5:1 light and ≥ 6:1 dark, all six (table above)
- [x] Neutrals verified in both modes
- [x] `prefers-reduced-motion` honoured, loops suppressed not shortened
- [x] Focus ring: 2px accent, 2px offset, never removed
- [x] No horizontal page scroll at 1280 / 390 / 320px, all 8 screens
- [x] Status carries a text label, not colour alone
- [ ] Full keyboard navigation — Phase 1
- [ ] Screen-reader labels on every icon-only control — Phase 1
- [ ] 44×44px touch targets audited — Phase 1 (nav and FAB already clear it)

Unchecked items are implementation work, not claims about the prototype.

## Verification

`mockup/tests/check.mjs` drives the prototype in Chromium and asserts that all
8 screens render, the countdown ticks, interactions change state, **all 12 seed ×
mode combinations produce distinct palettes**, `mode: system` resolves to a
concrete value rather than leaking through to the tokens, and no screen leaks
horizontal page scroll at 390px or 320px.

It has caught five real layout bugs so far, including two in this redesign: the
settings segmented control overflowing by 10px at 380px and 50px at 320px, and
an invisible selection ring on the accent picker (white on white, because the
rule used `currentColor`).
