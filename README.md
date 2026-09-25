# Firepower

NHL scores on your lock screen and Dynamic Island, with expected goals (xG) front and center.

Firepower is an iOS 18 app built around ActivityKit Live Activities. Pin your teams, start a game, and the score, clock, and xG battle stay live on your lock screen without opening the app. The xG bar is the thing the default Apple Sports widget doesn't give you: a team-colored bar showing who is actually generating the chances.

## Features

- **Live Activity per game** across all five surfaces: lock screen, Dynamic Island compact, expanded, and minimal.
- **Track several games at once** — start Live Activities for up to five games in parallel (the current iOS cap); Track disables once you're at the limit and re-enables when you stop one.
- **Team-colored design.** Each game uses the two teams' brand colors. A glance tells you who's playing before you read a single digit.
- **Team logos and names** in the daily game list, plus logos on every Dynamic Island surface. If a logo asset isn't available, it falls back to a team-colored tricode badge — same design language as the lock screen — so the UI never shows a broken image.
- **xG as a headline metric.** Bold expected-goals values plus a proportional team-colored bar.
- **Track opens 4 hours before puck drop.** Once the window opens, the Track button shows the scheduled start time (e.g. "6:00 PM") until the game begins, then flips to "Pregame" and finally to the live clock and xG on the first update. Earlier than that, the button shows when tracking opens instead of starting the activity too soon.
- **Stays around after the final horn.** When the game ends, the Live Activity switches to a "Final" score card — the winner's badge keeps showing its tricode, and the loser's score dims — and stays on your lock screen for about 4 hours, no need to catch it the moment the game ends.
- **Daily game list stays accurate for tracked games.** For any game you tracked, the list shows the real final score and xG (`Team 4 (xG: 3.10)`) and stops offering to track it the moment the Live Activity's push says the game is over — it doesn't wait on the slower NHL schedule API to catch up.
- **Daily game list** from the public NHL Stats API, with your pinned teams surfaced first.
- **Pre-game notifications** and background schedule refresh so the day's games are ready when you open the app.

## How it works

The app is a **pure APNs channel subscriber**. It never calls the Firepower backend directly. Game updates arrive two ways:

```
  NHL Stats API (api-web.nhle.com)         Firepower backend (separate repo)
            │                                          │
            │  daily schedule, scores                  │  live game updates
            ▼                                          ▼
      NHLScheduleClient                        APNs broadcast channel
            │                                  (one per team, e.g. nhl-team-BOS)
            ▼                                          │
        TodayView ──── start activity ──────────► Live Activity
                                              (FirepowerActivityKit widget)
```

- The daily game list comes from `api-web.nhle.com` via `NHLScheduleClient`.
- Live score/xG/event updates are delivered by APNs broadcast push to the team's channel. No running device or per-device registration is required; the backend pushes to the channel and every subscriber's Live Activity updates.
- When you start a game, `LiveActivityManager` requests the activity and subscribes to a team's channel — either team works, since the backend broadcasts each game on both teams' channels. You can track multiple games at once (up to the iOS limit, currently five); each runs as its own Live Activity.
- Live Activities outlive the app process — iOS routinely terminates a backgrounded app well before puck drop. On relaunch, `LiveActivityManager` rehydrates from the system's running activities, so the game list correctly shows what's already being tracked instead of resetting to untracked.
- When a game ends, the app — not the backend — decides how long the Live Activity stays visible. It keeps the activity alive and switches it to a "Final" score card the moment it sees the game-ending push, so the result stays on your lock screen for about 4 hours rather than disappearing right away. It also saves that final result for the day's game list, so the list reflects the outcome even after the Live Activity itself is gone.

**Offseason replay (Dev and TestFlight builds only).** From the end of the playoffs until the regular season starts, the real schedule has nothing worth tracking. In that window `OffseasonReplay` lists the same replayed games the backend is pushing, chosen exactly the way the `gameDataEmulator` chooses them: the app asks the NHL API whether the regular season has started, finds the day after the previous season's playoffs ended (day 0), and shows the bundled `season_2025-26.json` game-day at `days(day 0 → today)`, using the UTC date like the backend does. Those games are marked upcoming with scores cleared and start times shifted onto today (DST-aware), so you can start Live Activities against them. Nothing is hardcoded per season, so the app switches over on its own. If the NHL API can't answer, it falls back to normal regular-season behavior, and App Store builds never show replayed games. `Firepower/season_2025-26.json` must stay identical to the emulator's copy.

The wire format between backend and app is defined once in `FirepowerShared` and decoded by the widget. It is backward-compatible: the app degrades gracefully on an older backend.

## Project structure

| Target / package | What it is |
|---|---|
| `Firepower/` | Main app: daily game list (`TodayView`), pinned teams, settings, Live Activity lifecycle (`LiveActivityManager`), NHL schedule client, notifications |
| `FirepowerActivityKit/` | Widget extension: the Live Activity views for all five render surfaces (`FirepowerWidget`) |
| `FirepowerShared/` | Local Swift package shared by both targets: the wire-format contract (`FirepowerActivityAttributes`), color utilities (`NHLColor`), the 32-team palette (`NHLTeamColors`), the logo-fallback badge (`TeamTricodeBadge`), and dev-only preview overrides (`DebugFlags`) |

## Build and run

Requirements: Xcode 26+, iOS 18 simulator or device.

```bash
open Firepower.xcodeproj
```

Select the **Firepower** scheme and run. On first launch, pick your teams. To see a Live Activity without a live game, use the in-app Debug controls (DEBUG builds only) to start a fake BOS@NYR game and drive the score, clock, and xG by hand.

From the command line:

```bash
xcodebuild build -scheme Firepower \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Two schemes: real logos vs. tricode-only

The NHL team logo assets (`Assets.xcassets` imagesets, both app and widget targets) are official
league trademarks — they're vendored for convenience during development but aren't cleared for
commercial redistribution. Two schemes let you choose which version you ship:

| Scheme | Configuration | What ships |
|---|---|---|
| **Firepower** | `Release` | Real team logos everywhere |
| **Firepower-TricodeOnly** | `Release-TricodeOnly` | Team-colored tricode badges (`TeamTricodeBadge`) instead of logos — no compiler flag or source edit needed, it's automatic |

To archive a compliance-safe TestFlight/App Store build, pick **Firepower-TricodeOnly** in Xcode's
scheme picker (or **Product → Scheme**) before **Product → Archive**. The `Release-TricodeOnly`
build configuration sets `SWIFT_ACTIVE_COMPILATION_CONDITIONS = TRICODE_ONLY_BUILD` on the
`Firepower` and `FirepowerActivityKitExtension` targets; `GameRowView.teamImage` and
`FirepowerWidget.teamLogo` both check a local `tricodeOnlyBuild` constant driven by that flag,
alongside the existing `UIImage(named:)` presence check and the DEBUG-only `DebugFlags.forceTricodeFallback`
preview toggle. The normal **Firepower** scheme and `Release` configuration are unaffected —
real logos ship by default.

## Backend

The push backend is a Go service in a **separate repository** (`FirepowerApp/backend`). It watches NHL games and pushes Live Activity updates to the APNs broadcast channels. iOS and backend changes are separate PRs in separate repos. See [CLAUDE.md](CLAUDE.md) for the wire-format coordination and deployment order.

## More docs

- [CLAUDE.md](CLAUDE.md) — architecture, conventions, and backend coordination
- [DESIGN.md](DESIGN.md) — the design system (team-color rules, typography, the xG bar, accessibility)
- [TODOS.md](TODOS.md) — engineering debt surfaced during review, tracked alongside the code
