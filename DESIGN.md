# Firepower — Design System

Living document. Calibrate every UI decision against this. Update when a decision changes.

## Scope

Covers Live Activity widget (`FirepowerActivityKit`) and main app (`Firepower`). Initially seeded by `/plan-design-review` on 2026-05-31 (`live-activity-redesign` branch).

## Brand palette: NHL team colors are the system

Firepower does not have a Firepower brand color. The visual identity of each screen is the team(s) being displayed.

- Source of truth: `FirepowerShared/Sources/FirepowerShared/NHLTeamColors.swift` — `primaryColor`, `secondaryColor` hex per team. Both the app and the widget extension import `FirepowerShared`, so the palette lives in one place.
- `Firepower/NHLTeams.swift` holds the app-target team config (name, channel ID) but defers color to `NHLTeamColors`.
- Both fields are canonical. Never hand-pick a hex for a team in a view.

### Team color usage rules

All rules are implemented in `FirepowerShared/Sources/FirepowerShared/NHLColor.swift` (`NHLColor.badgeColors`).

1. **Primary first**: a team's color expression starts with `primaryColor`.
2. **Dark-primary contrast guard** (applied first): if a team's `primaryColor` has WCAG relative luminance < `0.015` (e.g. LAK `#111111`, SEA `#001628`, EDM `#041E42`), swap to `secondaryColor`. The threshold is deliberately low so deep-but-distinct colors like NYR royal blue (`#0038A8`, lum ~0.058) keep their primary.
3. **Collision rule** (applied second): if the two resolved colors are perceptually similar (normalized sRGB distance < `0.15` — practical examples: BOS/PIT gold, NYR/NYI blue), the **away** team swaps to its `secondaryColor`.
4. **Foreground on team fill**: text/glyph color on a team-colored fill prefers the team's `secondaryColor`, so both team colors appear on the badge (e.g. VGK steel-grey fill with a gold tricode). The secondary is used only when it clears a 3:1 contrast ratio against the fill (WCAG AA for large/bold text — the tricode is 12pt heavy); otherwise it falls back to white or black, whichever is more legible (`NHLColor.badgeTextColor`). This fallback covers the cases where the secondary equals the fill after the dark-primary guard (e.g. LAK silver) or two dark brand colors collide (NYR royal-blue fill + red secondary → white).

## Typography

System fonts only. SF Pro by default; rounded design for scores and numeric chrome.

| Role | Font | Notes |
|---|---|---|
| Score (widget) | `.system(.largeTitle, design: .rounded, weight: .heavy).monospacedDigit()` | Monospaced digits non-negotiable |
| Score (DI expanded) | `.title.weight(.bold).monospacedDigit()` | |
| Tricode badge | `.system(size: 12, weight: .heavy)` | On a 44×26 team-colored fill |
| Clock / period | `.subheadline.monospacedDigit()` | Always monospaced — clock ticks should not jitter |
| xG value | `.system(.title2, design: .rounded, weight: .heavy).monospacedDigit()` | The signature metric — sized to compete with the score |
| xG label ("xG") | `.subheadline.weight(.bold)` | Secondary, centered between the two values |
| Event line | `.caption.italic()` | Centered, no em-dashes ("Goal, Marchand") |
| App body | system default | TBD as main app gets redesigned |

## Dynamic Type

- Lock-screen widget: cap at `DynamicTypeSize.xLarge`. Live Activity height is fixed; larger sizes clip.
- Dynamic Island: cap at `DynamicTypeSize.large` (DI is tighter).
- Main app: full Dynamic Type support, no cap.

## Spacing scale

- Widget internal padding: 12pt vertical, 16pt horizontal.
- Lock-screen score row: team badge + score, 8pt interior spacing. The badge (not a logo) carries team identity here.
- Vertical gap between rows: 8pt.

## Signature element: xG bar

xG is the metric that sets this app apart from the default Apple Sports widget, so it reads as a highlight on the lock screen, not a footnote. The two values are shown to **two decimal places** (`%.2f`) so small, in-game xG swings are legible.

Below the bold values sit **two stacked team-colored capsule bars** — the home bar grows from the left edge, the away bar from the right edge — that encode the xG **gap**, not each team's raw share. At an even xG both bars own half the width; every 1.0 of separation shifts the split by half the width toward the leader (so a 1.40–1.00 edge reads as 70 / 30). The trailing team always keeps a small visible sliver (clamped to 2%), and a 0-0 game lands at 50/50 so it never implies one team is dominating. A swing toward one team visibly lengthens its bar while the other retracts. Implemented in `XGSection` (`FirepowerWidget.swift`).

Sensitivity note: because the split is half-width per 1.0 of xG, a gap of ≥ 1.0 saturates the leader's bar to full width. That keeps mid-game swings dramatic and readable; revisit the scale if real games routinely peg the bar.

## Iconography

- Team logos: PNG assets in `Assets.xcassets`, lowercase tricode (`bos.png`). Resolved via `teamLogo(_:size:)` helper. Falls back to tricode text if asset missing. Used in Dynamic Island (compact/minimal/expanded); the lock screen uses team-colored badges instead.
- No emoji. No SF Symbol decoration in the widget.

## Motion

**Policy for v1: none.** Live Activity updates are silent visual transitions. The OS provides the haptic / notification cue when a new push lands; we do not add app-level animation on top.

Reconsider if user feedback shows scoring feels muted. Documented decision: D4 in `live-activity-redesign.md`.

## Accessibility floor

- VoiceOver: the lock-screen Live Activity collapses its score row + clock + xG + event into one spoken sentence via `.accessibilityElement(children: .ignore)` + an explicit `.accessibilityLabel(...)`.
- Label template: *"{Home name} {homeScore}, {Away name} {awayScore}, {gameState}, expected goals {homeXG} to {awayXG}.{event sentence if present}."*
- Contrast: 4.5:1 minimum for any text rendered on a team-color fill. Verified per team-color rule above.
- Touch targets in main app: 44pt minimum.

## What this document is not

- Not a Firepower brand book. There is no Firepower-the-app primary color, mascot, or typography signature. The app is a clean lens onto the league.
- Not exhaustive for the main app yet. Live Activity is fully spec'd; `Firepower/` main-app screens (`TodayView`, `SettingsView`, `TeamPickerView`) inherit the palette + typography rules but are not yet pass-reviewed at this level.
