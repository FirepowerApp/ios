# Firepower

NHL scores on your lock screen and Dynamic Island, with expected goals (xG) front and center.

Firepower is an iOS 18 app built around ActivityKit Live Activities. Pin your teams, start a game, and the score, clock, and xG battle stay live on your lock screen without opening the app. The xG bar is the thing the default Apple Sports widget doesn't give you: a team-colored bar showing who is actually generating the chances.

## Features

- **Live Activity per game** across all five surfaces: lock screen, Dynamic Island compact, expanded, and minimal.
- **Track several games at once** — start Live Activities for up to five games in parallel (the current iOS cap); Track disables once you're at the limit and re-enables when you stop one.
- **Team-colored design.** Each game uses the two teams' brand colors. A glance tells you who's playing before you read a single digit.
- **xG as a headline metric.** Bold expected-goals values plus a proportional team-colored bar.
- **Start tracking early.** Kick off a Live Activity hours before puck drop — it shows the scheduled start time (e.g. "6:00 PM") until the game begins, then flips to "Pregame" and finally to the live clock and xG on the first update.
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

**Offseason replay.** During the NHL offseason (June 22 – September 30) the real schedule is empty, so there is nothing to track. In that window `OffseasonReplay` maps today onto the corresponding real 2025-26 date and slides those games onto the daily list — marked upcoming with scores cleared and start times shifted (DST-aware) — so you can still start Live Activities against replayed games. Outside the window it is a no-op and the in-season path is unchanged.

The wire format between backend and app is defined once in `FirepowerShared` and decoded by the widget. It is backward-compatible: the app degrades gracefully on an older backend.

## Project structure

| Target / package | What it is |
|---|---|
| `Firepower/` | Main app: daily game list (`TodayView`), pinned teams, settings, Live Activity lifecycle (`LiveActivityManager`), NHL schedule client, notifications |
| `FirepowerActivityKit/` | Widget extension: the Live Activity views for all five render surfaces (`FirepowerWidget`) |
| `FirepowerShared/` | Local Swift package shared by both targets: the wire-format contract (`FirepowerActivityAttributes`), color utilities (`NHLColor`), and the 32-team palette (`NHLTeamColors`) |

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

## Backend

The push backend is a Go service in a **separate repository** (`FirepowerApp/backend`). It watches NHL games and pushes Live Activity updates to the APNs broadcast channels. iOS and backend changes are separate PRs in separate repos. See [CLAUDE.md](CLAUDE.md) for the wire-format coordination and deployment order.

## More docs

- [CLAUDE.md](CLAUDE.md) — architecture, conventions, and backend coordination
- [DESIGN.md](DESIGN.md) — the design system (team-color rules, typography, the xG bar, accessibility)
