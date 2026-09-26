# Firepower iOS

NHL hockey Live Activity app. Shows scores on the lock screen and Dynamic Island via APNs broadcast push. Includes a daily game list (NHL Stats API), pinned teams, pre-game notifications, and background schedule refresh.

## Planning docs

Planning materials live in a local working directory outside this repo (referred to as `$PLANNING` below). They are not committed here:
- `todos.md` — personal/external deferred work with priority, scratch-level, not committed
- `test-plan-*.md` — QA test plan
- `backend/` — scratch copies of backend Go files for local iteration; copy into your local `FirepowerApp/backend` clone when ready (see Backend repo section below)
- `live-activity-redesign.md` — design + eng review plan for the Live Activity redesign (branch: `NelsonBlakeN/live-activity-redesign`)

Separately, [`TODOS.md`](TODOS.md) at the repo root **is committed** — it tracks engineering debt
surfaced during review (e.g. `/review`, `/plan-eng-review`) that should travel with the code
instead of living only in `$PLANNING`. The two lists are not the same thing: `$PLANNING/todos.md`
is yours; `TODOS.md` is the project's.

## Time zones: device-local only, never UTC

The client always determines "today" — which games belong on the home game list, cache
freshness, offseason replay's day index, anything answering "what day is it right now" —
using the **device's own local time zone** (`TimeZone.current` / `Calendar.current`).

**Never key client-side "today" logic to UTC or any other fixed time zone.** UTC is a
backend/network-boundary format for exchanging instants (wire timestamps, `startTimeUTC`),
not a reference frame for deciding what a user sees "today." A client that computes its
own day boundary in UTC (or ET, or any zone other than the device's) will show the wrong
day's games to a user in a different time zone, near midnight, or across a DST change —
that class of bug is explicitly out of bounds here, no matter how it's justified (e.g.
"matching a backend convention"). If a wire format or backend service is genuinely UTC-
keyed and something needs to line up with it, resolve the mismatch on the backend side or
accept the mismatch — don't make the client's own day boundary UTC to compensate.

`OffseasonReplay.todayString()` (dev/TestFlight-only offseason game selection) takes an
explicit `timeZone` parameter for testability, but defaults to `.current` and must keep
doing so.

## Architecture: iOS app is a pure APNs channel subscriber

**The iOS app never makes direct HTTP calls to the Firepower backend.**

All game data reaches the app exclusively via APNs broadcast push to the team's channel.
Channel IDs are created in App Store Connect → App ID → Push Notifications → Broadcast
Notifications, and hardcoded in `Firepower/NHLTeams.swift` in the `debugChannelIds`
(development) and `prodChannelIds` (release/TestFlight/App Store) maps, resolved by
build config via `channelId(for:)`.

Do not add URLSession calls, REST clients, or any other direct backend communication
to the app target. If schedule/game data is needed in the UI, it either:
- arrives through the APNs channel push payload, or
- comes from the public NHL Stats API (api-web.nhle.com) — never from the Firepower backend.

## APNs broadcast push endpoint

```
POST https://api.sandbox.push.apple.com/4/broadcasts/apps/{bundleID}

Headers:
  authorization:   bearer {jwt}       ← ES256 JWT signed with .p8 key
  apns-push-type:  liveactivity
  apns-channel-id: {channelID}        ← base64 channel ID from App Store Connect; NOT in URL
  apns-expiration: {unix timestamp}   ← required (non-zero) for "No Message Stored" channels
  content-type:    application/json

NOTE: apns-topic is NOT used. The bundle ID is in the URL path.
NOTE: no running device/activity is required to push to a channel.
```

iOS app entitlement required: `com.apple.developer.usernotifications.broadcasting`

## Stack

- iOS 18+ / Swift / SwiftUI / ActivityKit
- Widget extension target: FirepowerActivityKit
- Bundle ID: com.blakenelson.Firepower
- Team ID: 89T7Q7LS36
- Backend: Go, in the **separate `FirepowerApp/backend` repo** — separate PRs

## Backend repo

The push backend is a separate repository: `FirepowerApp/backend`. Clone it wherever you like (paths below use `$BACKEND` for your local clone).

**Do not commit backend changes in this iOS repo.** Backend changes go to `FirepowerApp/backend` and are submitted as separate PRs there.

The backend planning scratch (a local-only draft area, e.g. `$PLANNING/backend/`) is where you iterate on backend changes before copying them into your `$BACKEND` clone. When ready, copy them across:

```bash
cp "$PLANNING/backend/watchgameupdates/internal/notification/liveactivity/formatter.go" \
   "$BACKEND/watchgameupdates/internal/notification/liveactivity/formatter.go"
# repeat for other changed files, then: cd "$BACKEND" && git commit
```

## iOS ↔ Backend wire format coordination

Only the dynamic `ContentState` crosses the wire. The iOS `ContentState` (in `FirepowerShared`) and the backend `contentState` struct in `formatter.go` must stay in sync. When changing the wire format:

**Static attributes are iOS-only — they never need backend coordination.** Fields on `FirepowerActivityAttributes` itself (`sport`, `homeTeam`, `awayTeam`, `gameID`, `pinnedTricode`, `startTime`) are set once by iOS at `Activity.request` time and are never pushed. `startTime`, for example, is the scheduled puck drop the app already knows from the NHL schedule; it drives the pregame time display with no backend involvement. Adding a static attribute is a pure iOS change. The sync rules below apply only to `ContentState`.

**The backend never sends `aps.event: "end"` — the iOS client alone decides when a Live Activity ends.** A push with `event:"end"` is applied by the OS directly, with no app code in the loop (see "no running device/activity is required to push to a channel" above), so once the backend sends it there is no point where the app can reconsider the dismissal timing. The backend always sends `event:"update"`, including on the final push (content `gameState:"Final"`, a long stale-date, but the activity stays alive). `LiveActivityManager.endIfFinal` ends the activity itself the moment it observes `isEnded`, with its own dismissal window. Any change to `formatter.go`'s `aps.event` logic must preserve this — reintroducing `event:"end"` forecloses the client's ability to control anything about how the game-over state is presented.

1. **Backend branch first:** Create the backend branch (e.g. `NelsonBlakeN/live-activity-event-fields`) in the `FirepowerApp/backend` repo.
2. **iOS is backward-compatible by default:** `ContentState` decodes new fields as optional and falls back to legacy fields (`lastEvent`) via `resolved*` accessors. The iOS change can ship **before or after** the backend change.
3. **Deployment order (recommended):** Ship the iOS update first (App Store review takes ~24h), then deploy the backend. The iOS app degrades gracefully on the old backend.
4. **Remove legacy fields** once the new backend has been live for one release cycle and `lastEvent` is no longer emitted. The `private var lastEvent` field in `ContentState` is explicitly marked for removal.

## Key files

- `Firepower/` — main app target (TodayView, LiveActivityManager, FirepowerApp, NHLScheduleClient, OffseasonReplay)
- `Firepower/LiveActivityManager.swift` — Live Activity lifecycle. `rehydrate()`/`rehydratePlan` reconcile tracked state against the OS's running activities on every foreground; `endIfFinal` is the only place in the app that ends a finished game's activity (see the wire-format section above). `TodayView`'s `reconcile()` calls `rehydrate()` on cold launch and every scenePhase transition to `.active`. Also owns `finishedGames`: the moment a tracked game's push reaches Final, its result (score + xG) is captured into a persisted `FinishedGame` record — captured on every path that can retire a game from `tracked` (the live `.ended` observer, `rehydrate()`'s prune path for a game that finished while the app wasn't running, and `stopActivity()`) so `GameRowView` can show the real result and hide the Track button even after the schedule API or the Live Activity itself has gone stale.
- `Firepower/OffseasonReplay.swift` + `Firepower/season_2025-26.json` — offseason game selection, mirroring the emulator (`FirepowerApp/gameDataEmulator`). The bundled JSON must stay identical to the emulator's `internal/services/data/season_2025-26.json`. When the live NHL API says the regular season hasn't started (`regularSeasonStartDate`), `resolveAnchor` finds day 0 (the day after the previous season's playoffs, via a `previousStartDate` walk-back — nothing hardcoded per season) and today (the device's local date — see "Time zones" above) maps to the dense `gameDays[days(anchor → today)]`, rebased onto today (FUT, scores cleared, DST-aware). API failure → regular-season behavior. Gated by `BuildEnvironment.showsReplayedGames` (Dev/TestFlight only). Pinned tests in `FirepowerTests`.
- `Firepower/NHLTeams.swift` — static config for all 32 teams: `tricode`, `name`, `shortName` (mascot only, e.g. "Penguins" — rendered next to the logo/badge in `GameRowView`, since the tricode already appears inside it), channel IDs. Color lives in `NHLTeamColors` (`FirepowerShared`), not here.
- `FirepowerShared/` — local Swift package shared by app and widget (FirepowerActivityAttributes, NHLColor, NHLTeamColors, TeamTricodeBadge, DebugFlags)
- `FirepowerActivityKit/` — widget extension (FirepowerWidget, FirepowerActivityKitBundle)
- `FirepowerShared/Sources/FirepowerShared/FirepowerActivityAttributes.swift` — single source of truth for wire format; both targets import `FirepowerShared`
- `DESIGN.md` — design system for the Live Activity + app (team-color rules, typography, xG bar, accessibility floor)

## Team logos: two build configurations

`Assets.xcassets` in both the app and widget targets vendors the real NHL team logo SVGs
(`{team}.imageset`) for local development, but they're licensed league trademarks, not cleared
for commercial redistribution. `Firepower/GameRowView.swift` and `FirepowerActivityKit/FirepowerWidget.swift`
both render a logo only if `UIImage(named:)` finds the asset **and** two build-time gates are
clear; otherwise they fall back to `FirepowerShared/Sources/FirepowerShared/TeamTricodeBadge.swift`
— a team-colored badge that reuses the lock screen's `NHLColor.badgeColors` collision-resolution
logic so it reads as the same design language, not a broken-image placeholder.

- **`DebugFlags.forceTricodeFallback`** (`FirepowerShared/Sources/FirepowerShared/DebugFlags.swift`) — a DEBUG-only
  dev toggle to preview the fallback in the simulator. Hardcoded `false` outside `#if DEBUG`, so it
  cannot affect a Release build regardless of its value.
- **`Release-TricodeOnly`** build configuration (Firepower project + all 4 targets) sets
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS = TRICODE_ONLY_BUILD` on the `Firepower` and
  `FirepowerActivityKitExtension` targets. The **`Firepower-TricodeOnly`** scheme's Run/Profile/Archive
  actions build against it. Archiving from that scheme is the actual mechanism for shipping a
  compliance-safe TestFlight/App Store build without the licensed logo assets — pick the scheme,
  no source changes needed. The normal `Firepower` scheme / `Release` configuration ship real logos
  and are untouched by any of this.
