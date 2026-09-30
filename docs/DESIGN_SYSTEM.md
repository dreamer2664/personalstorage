# Design system

A macOS/iOS-flavoured **glass** look: translucent frosted surfaces over a softly drifting colour field,
squircle corners, Inter typography, subtle shadows, springy motion. Everything lives in
`lib/core/design` and is consumed through `context.ps` (palette) - screens never hard-code colours.

## Tokens (`tokens.dart`)

| Token | Values |
|---|---|
| Palette | `PsPalette.light` / `.dark`: background, glass fill (translucent), hairline border, separators, 3 label levels, accent `#0A84FF`, semantic colours, ambient blob colours |
| Category colours | iOS system palette, one per ontology domain (`category_style.dart`): Shopping orange, Health pink-red, Finance green, Work indigo, Tech blue, Travel teal ... plus a neutral *General* |
| Spacing | 4-pt grid (`PsSpace`) |
| Radii | chip 12, card 22, bar 26, sheet 28 - all **continuous corners** (`RoundedSuperellipseBorder`) |
| Type (Inter) | largeTitle 34/700 · title 22/600 · headline 17/600 · body 17 · subhead 15 · footnote 13 · caption 12; negative tracking like SF Pro |
| Motion | fast 140 ms · base 260 ms · slow 420 ms; `easeOutCubic`, emphasized `Cubic(.2,0,0,1)`, `easeOutBack` for pops |

## Glass rules (`glass.dart`)

1. **Backdrop blur only on chrome** - tab bar, composer, toasts, graph overlays, selection cards. It is the most
   expensive effect in Flutter; repeating list cards use the translucent fill *without* blur, which is visually
   near-identical and an order of magnitude cheaper.
2. `GlassPanel` = translucent fill + optional `BackdropFilter` + hairline highlight border + two-layer soft shadow,
   clipped to the squircle.
3. `AmbientBackground` paints 4 drifting radial gradients (no blur filter), so the glass always has colour to refract.
4. `PressableScale` gives every tappable surface the same weight (0.97 scale, 140 ms).

## Motion and micro-interactions

* Insight chips **pop in** only when new (keyed), while the row animates its height.
* List items **fade + slide** with a 35 ms stagger (first 8 only).
* Tab bar: a **sliding selection pill**, icon scale spring, hide-on-keyboard slide.
* Checkbox: spring-scaled fill with a checkmark; completed text strikes through with an animated text style.
* Graph: camera eases with a critically damped follower; nodes settle under the simulation; inertia on pan.
* Haptics (selection/light/medium/heavy) mapped to intent; one switch in Settings disables them.

## Accessibility

* Every icon button has a semantic label (used by `tool/web_shots.py` and by screen readers): *Save note*,
  *Start voice note*, *Attach photo*, tab names, *Settings*, *Fit to screen* ...
* Layouts are tested with **2.4x text scale** (no overflow), in light and dark mode.
* Status is never colour-only (icons + text on chips, strike-through for done tasks).
* Tap targets are >= 40 px; the primary capture controls are 52-72 px.
* Known gap: the graph canvas is pointer-driven and has no semantic tree; everything it shows is also
  reachable through Library search and the note detail "Related" list.

## Dark mode

All colours come from the palette, the ambient blobs switch to deep violet/blue, glass fills become
dark translucent, borders become 12% white. The app follows the system setting unless overridden in Settings.
