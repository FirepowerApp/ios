# Firepower — Design System

Living document. Calibrate every UI decision against this. Update when a decision changes.

## Scope

Covers Live Activity widget (`FirepowerActivityKit`) and main app (`Firepower`). Initially seeded by `/plan-design-review` on 2026-05-31 (`live-activity-redesign` branch).

## Brand palette: NHL team colors are the system

Firepower does not have a Firepower brand color. The visual identity of each screen is the team(s) being displayed.

- Source of truth: `Firepower/NHLTeams.swift` — `primaryColor`, `secondaryColor` hex per team.
- Both fields are canonical. Never hand-pick a hex for a team in a view.
- Make `NHLTeams.swift` Target Membership = both `Firepower` and `FirepowerActivityKit` (widget extension needs it).

### Team color usage rules

1. **Primary first**: a team's color expression starts with `primaryColor`.
2. **Collision rule**: if two teams shown together have visually similar primaries (Delta-E < ~25 — practical examples: BOS/PIT gold, NYR/NYI blue, MTL/COL maroon), the **away** team swaps to its `secondaryColor`.
3. **Dark-primary contrast guard**: if a team's `primaryColor` has perceived luminance < 0.25 (e.g. LAK `#111111`, SEA `#001628`, EDM `#041E42`), swap to `secondaryColor` whenever the fill sits on the widget's dark background.
4. **Foreground on team fill**: text/glyph color on a team-colored fill = white if fill luminance < 0.5, else the team's `secondaryColor`. Always verify resulting contrast >= 4.5:1.

## Typography

System fonts only. SF Pro by default; rounded design for scores and numeric chrome.

| Role | Font | Notes |
|---|---|---|
| Score (widget) | `.system(.largeTitle, design: .rounded, weight: .heavy).monospacedDigit()` | Monospaced digits non-negotiable |
| Score (DI expanded) | `.title.weight(.bold).monospacedDigit()` | |
| Tricode badge | `.caption.weight(.bold)` | |
| Clock / period | `.subheadline.monospacedDigit()` | Always monospaced — clock ticks should not jitter |
| xG row | `.caption.monospacedDigit()` | Secondary foreground |
| Last event | `.caption.italic()` | |
| App body | system default | TBD as main app gets redesigned |

## Dynamic Type

- Lock-screen widget: cap at `DynamicTypeSize.xLarge`. Live Activity height is fixed; larger sizes clip.
- Dynamic Island: cap at `DynamicTypeSize.large` (DI is tighter).
- Main app: full Dynamic Type support, no cap.

## Spacing scale

- Widget internal padding: 12pt vertical, 16pt horizontal.
- Score row interior spacing: 8pt between logo and score number, 6pt between badge and logo.
- Vertical gap between rows: 6pt.

## Iconography

- Team logos: PNG assets in `Assets.xcassets`, lowercase tricode (`bos.png`). Resolved via `teamLogo(_:size:)` helper. Falls back to tricode text if asset missing.
- No emoji. No SF Symbol decoration in the widget.

## Motion

**Policy for v1: none.** Live Activity updates are silent visual transitions. The OS provides the haptic / notification cue when a new push lands; we do not add app-level animation on top.

Reconsider if user feedback shows scoring feels muted. Documented decision: D4 in `live-activity-redesign.md`.

## Accessibility floor

- VoiceOver: every Live Activity surface combines its score row + clock + event into one sentence via `.accessibilityElement(children: .combine)` + `.accessibilityLabel(...)`.
- Label template: *"{Home name} {homeScore}, {Away name} {awayScore}, {gameState}, expected goals {homeXG} to {awayXG}.{event sentence if present}."*
- Contrast: 4.5:1 minimum for any text rendered on a team-color fill. Verified per team-color rule above.
- Touch targets in main app: 44pt minimum.

## What this document is not

- Not a Firepower brand book. There is no Firepower-the-app primary color, mascot, or typography signature. The app is a clean lens onto the league.
- Not exhaustive for the main app yet. Live Activity is fully spec'd; `Firepower/` main-app screens (`TodayView`, `SettingsView`, `TeamPickerView`) inherit the palette + typography rules but are not yet pass-reviewed at this level.
