# Design

> Scene: someone on a sofa at 11pm with the lights off, an 11" Android tablet in their hands, choosing tonight's film. The screen must glow softly, never glare, and the user's own artwork must be the most beautiful thing on it.

Implementation lives in `lib/ui/` (`tokens.dart`, `components.dart`, `artwork_tint.dart`). Never hard-code a colour, radius or duration in a feature file; use the tokens.

## Visual Theme

Dark, low-glare, cinematic and quiet. Closest reference: the Apple TV app. Chrome is thin graphite; artwork supplies all colour. Light itself (a soft, slightly cool near-white) is the only accent: the primary "Play" pill, focus rings, progress, selected tabs.

Explicitly not: stock Material (pill nav indicators, tonal chips, FAB-style buttons, ink ripples), gold/red "streaming" accents, neon, gradient text, glass on every surface.

## Colour (Restrained strategy)

Neutrals are tinted toward a cool graphite (hue ≈ 255, very low chroma). No pure black, no pure white.

| Token | Hex | Role |
|---|---|---|
| `bg` | `#0B0C0F` | App background, scrims fade into it |
| `surface1` | `#141619` | Grouped lists, nav capsules, panels |
| `surface2` | `#1B1E22` | Hover, pressed rows, menus, dialogs |
| `surface3` | `#24282D` | Placeholders, tracks |
| `hairline` | `#E9ECF2` @ 8% | Separators, poster edge |
| `text` | `#ECEEF2` | Primary text (≈ 16:1 on bg) |
| `text2` | `#9DA3AD` | Secondary text, meta lines (≈ 7.4:1) |
| `text3` | `#767C86` | Tertiary labels only (≈ 4.6:1) |
| `light` | `#F1F3F6` | Primary action fill, focus ring, progress, selection |
| `onLight` | `#0B0C0F` | Text/icons on `light` |
| `danger` | `#E2685E` | Errors, destructive rows |

**Artwork tint:** detail pages sample the poster/backdrop and lay a desaturated, dark glow of its dominant colour behind the content. This is the only place colour appears outside artwork.

## Typography

System font stack (Roboto + Noto Sans CJK on Android, SF + PingFang on Apple, Segoe + YaHei on Windows). One family; hierarchy by size and weight, ratio ≈ 1.2.

| Style | Size / weight | Use |
|---|---|---|
| `display` | 40 / 700, −0.8 tracking | Hero and detail titles (tablet) |
| `largeTitle` | 30 / 700, −0.5 | Page titles |
| `title` | 21 / 600, −0.2 | Section headers |
| `headline` | 16 / 600 | Card titles, row titles |
| `body` | 15 / 400, 1.6 line height | Plot, descriptions (max ≈ 65ch) |
| `callout` | 14 / 500 | Buttons, tabs |
| `caption` | 12.5 / 500, text2 | Meta under posters |
| `overline` | 12 / 600, +0.6 tracking, text3 | Small section labels, episode numbers |

## Layout

- Gutters: phone 20, tablet 32, desktop 48.
- Vertical rhythm between home shelves: 36; inside a shelf header → content: 12.
- Radii: poster 10, landscape card 12, grouped list 14, dialog 22, pills fully round.
- Tablet / desktop navigation: a floating blurred capsule at the top with text tabs; settings behind a gear. Phone: a blurred bottom bar with icon + label, no indicator pill.
- Content scrolls under the navigation; pages reserve space through `ShellInsets`.

## Components

- **PillButton**: primary = `light` fill + `onLight` label; secondary = 12% light fill + `text` label. Height 48. No ripple; pressed = 70% opacity.
- **RoundIconButton**: 44–48 circle, 10% light fill (blurred when over artwork).
- **FilterPills**: text pills; selected = `light` fill, unselected = `text2` text on nothing.
- **PosterCard**: 2:3 image, 1px hairline edge, title + year below. Hover / focus: 3% scale and a 2px `light` focus ring (keyboard / D-pad). Watched = small light check; in-progress = 3px light hairline at the bottom.
- **GroupedList / SettingRow**: iOS-settings-like grouped surface with inset hairlines. Never cards inside cards.
- **Hero**: full-bleed backdrop, bottom and left scrims into `bg`, logo or title bottom-left, one primary pill.

States: every pressable has default, hover (2–4% light overlay), keyboard focus (light ring), pressed (opacity), disabled (40% opacity).

## Motion

Minimal by request. 160–220 ms, ease-out-quart (`Cubic(0.25, 1, 0.5, 1)`), opacity and small scale only. No slides, no bounces, no orchestrated loads. When `MediaQuery.disableAnimations` is on, all durations become zero.
