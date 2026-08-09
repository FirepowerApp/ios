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

All rules are implemented in `FirepowerShared/Sources/FirepowerShared/NHLColor.swift` (`NHLColor.badgeColors`, `NHLColor.needsVisibilityOutline`).

1. **Primary first**: badge fill and xG bar always start with `primaryColor`. Neither is ever swapped to `secondaryColor` as the fill.
2. **Visibility outline** (caller responsibility): when a fill's WCAG luminance < `0.015`, `NHLColor.needsVisibilityOutline(_:)` returns `true` and the view adds a white stroke outline (`opacity: 0.45` on badges, `0.4` on xG capsules) so the shape reads on the near-black widget background. This keeps dark-navy teams (LAK, SEA, EDM, FLA, NSH, WSH, WPG — all `lum < 0.015`) on their real primary color instead of swapping to their accent. NYR royal blue (`#0038A8`, lum ~0.058) and STL blue (`#002F87`, lum ~0.038) are below the knee but above 0.015 — they do not need an outline.
3. **Collision rule**: if the home and away primaries are perceptually similar (normalized sRGB distance < `0.15`), a three-level resolution applies:
   - **Level 1** — away secondary viable (lum ≥ 0.015): away swaps to its secondary. E.g. NYR/NYI blue → NYI uses orange.
   - **Level 2** — away secondary dark, home secondary viable: home swaps to its secondary (bidirectional flip). E.g. DET home vs CHI away (both red): DET flips to its white secondary; CHI stays red.
   - **Level 3 (both-fail)** — both secondaries dark (lum < 0.015): white is tried first. If home primary clears 3:1 on white, home fills white and renders its primary as tricode text (e.g. red "NJD" on white at 5.6:1). If home primary fails on white (e.g. BOS/PIT gold at 1.7:1), home fills its black secondary (outlined in white) and renders its primary as text (gold "BOS" on black at 12:1). The away team always keeps its primary fill for both badge and bar. Badge fill always equals bar color — no exceptions.
4. **Foreground on team fill**: text/glyph color on a team-colored fill prefers the team's `secondaryColor` when it clears a 3:1 contrast ratio against the fill (WCAG AA for 12pt heavy text); otherwise falls back to white or black, whichever is more legible (`NHLColor.badgeTextColor`). For dark-navy fills the secondary (typically a bright accent) passes contrast easily, so the tricode renders in the accent color on the navy badge.
5. **Winner badge**: the winning team's badge always shows its tricode. No "WIN" label. The winner is signaled by the loser's score dimming to 55% opacity.

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

**Main app exception — daily game list.** A completed game's row in `TodayView`'s list
(`GameRowView.teamRow`) shows xG as plain text next to each team's score —
`"{team} {score} (xG: {value})"` — not the capsule bar. Deliberate: the bar's team-colored
capsules are tuned for the widget's near-black background (`activityBackgroundTint`) and read
poorly on the list row's light `secondarySystemGroupedBackground`; the list also only ever shows
xG for a game once it's Final (sourced from the persisted push result), never live, so the bar's
in-game "which way is it swinging" motion isn't the point there — a static reference value is.

## Iconography

- Team logos: SVG imagesets in `Assets.xcassets` (light/dark variants), lowercase tricode (`bos.imageset`). Resolved via `teamLogo(_:homeTricode:awayTricode:size:)` (widget) / `GameRowView.teamImage` (app). Falls back to `TeamTricodeBadge` — a team-colored tricode badge reusing the lock screen's collision-resolution rules — if the asset is missing, not plain text. Used in the daily game list and every Dynamic Island surface (compact/minimal/expanded); the lock screen uses its own fixed-size team-colored badge (`TeamBadge`) instead of a logo.
- The fallback isn't just a missing-asset safeguard: a dedicated `Release-TricodeOnly` build configuration/scheme ships the badge everywhere on purpose, since the logo assets are licensed NHL trademarks. See "Team logos: two build configurations" in `CLAUDE.md`.
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
