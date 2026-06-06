# Firepower iOS

NHL hockey Live Activity app. Shows scores on the lock screen and Dynamic Island via APNs broadcast push. Includes a daily game list (NHL Stats API), pinned teams, pre-game notifications, and background schedule refresh.

## Planning docs

Planning materials live in a local working directory outside this repo (referred to as `$PLANNING` below). They are not committed here:
- `todos.md` — deferred work with priority
- `test-plan-*.md` — QA test plan
- `backend/` — scratch copies of backend Go files for local iteration; copy into your local `FirepowerApp/backend` clone when ready (see Backend repo section below)
- `live-activity-redesign.md` — design + eng review plan for the Live Activity redesign (branch: `NelsonBlakeN/live-activity-redesign`)

## Architecture: iOS app is a pure APNs channel subscriber

**The iOS app never makes direct HTTP calls to the Firepower backend.**

All game data reaches the app exclusively via APNs broadcast push to the team's channel.
Channel IDs are created in App Store Connect → App ID → Push Notifications → Broadcast
Notifications, and hardcoded in `Firepower/NHLTeams.swift` under `channelTokenBase64`.

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

The iOS `ContentState` (in `FirepowerShared`) and the backend `contentState` struct in `formatter.go` must stay in sync. When changing the wire format:

1. **Backend branch first:** Create the backend branch (e.g. `NelsonBlakeN/live-activity-event-fields`) in the `FirepowerApp/backend` repo.
2. **iOS is backward-compatible by default:** `ContentState` decodes new fields as optional and falls back to legacy fields (`lastEvent`) via `resolved*` accessors. The iOS change can ship **before or after** the backend change.
3. **Deployment order (recommended):** Ship the iOS update first (App Store review takes ~24h), then deploy the backend. The iOS app degrades gracefully on the old backend.
4. **Remove legacy fields** once the new backend has been live for one release cycle and `lastEvent` is no longer emitted. The `private var lastEvent` field in `ContentState` is explicitly marked for removal.

## Key files

- `Firepower/` — main app target (TodayView, LiveActivityManager, FirepowerApp, NHLScheduleClient)
- `FirepowerShared/` — local Swift package shared by app and widget (FirepowerActivityAttributes, NHLColor, NHLTeamColors)
- `FirepowerActivityKit/` — widget extension (FirepowerWidget, FirepowerActivityKitBundle)
- `FirepowerShared/Sources/FirepowerShared/FirepowerActivityAttributes.swift` — single source of truth for wire format; both targets import `FirepowerShared`
- `DESIGN.md` — design system for the Live Activity + app (team-color rules, typography, xG bar, accessibility floor)
