# Firepower iOS

NHL hockey Live Activity app. Shows score + MoneyPuck xG data on lock screen and Dynamic Island.

## Planning docs

All design decisions, todos, test plan, and backend Go files are at:

```
~/Documents/Firepower/planning/
```

Key files:
- `design-20260504-094508.md` — full design doc (CEO, design, eng reviews done)
- `todos.md` — 16 deferred items with priority
- `test-plan-20260504.md` — QA test plan
- `XCODE-SETUP.md` — one-time Xcode setup (already completed)
- `backend/` — Go files for the liveactivity notification package (copy to ~/git/Firepower/backend/)

To resume from a checkpoint:
```
/checkpoint resume
```

## Project state

- v1 end-to-end verified: Live Activity starts, broadcast push received, lock screen + Dynamic Island update correctly
- Broadcast push channel confirmed working (sandbox, App Store Connect channel `+pSGy0vgEfEAAKqhstn/Jg==`)
- v2 shipped: daily game list (NHL Stats API), pinned teams, settings, local notifications, BGAppRefreshTask morning fetch
- Pre-game notifications (10 min before puck drop for pinned teams) deep-link into app and auto-start the Live Activity
- Next: seed initial ContentState from live-scores API when starting a mid-game Live Activity

## Architecture: iOS app is a pure APNs channel subscriber

**The iOS app never makes direct HTTP calls to the Firepower backend.**

All game data reaches the app exclusively via APNs broadcast push to the team's channel.
Channel IDs are created in App Store Connect → App ID → Push Notifications → Broadcast
Notifications, and hardcoded in `Firepower/NHLTeams.swift` under `channelTokenBase64`.

Do not add URLSession calls, REST clients, or any other direct backend communication
to the app target. If schedule/game data is needed in the UI, it either:
- arrives through the APNs channel push payload, or
- comes from the public NHL Stats API (api-web.nhle.com) — never from the Firepower backend.

## APNs broadcast push — correct endpoint (verified 2026-05-10)

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

Errors encountered during discovery:
- `BroadcastFeatureNotEnabled` — enable Broadcast Push in App Store Connect for the App ID
- `ChannelNotRegistered`       — channel ID not created in App Store Connect yet
- `BadPath`                    — wrong URL structure (not `/3/live-activity/` or `/3/device/`)

iOS app entitlement required: `com.apple.developer.usernotifications.broadcasting`

## Stack

- iOS 18+ / Swift / SwiftUI / ActivityKit
- Widget extension target: FirepowerActivityKit
- Bundle ID: com.blakenelson.Firepower
- Team ID: 89T7Q7LS36
- Backend: Go, at ~/git/Firepower/backend/

## Key files

- `Firepower/` — main app target (ContentView, LiveActivityManager, FirepowerApp)
- `FirepowerActivityKit/` — widget extension (FirepowerWidget, FirepowerActivityAttributes)
- `FirepowerActivityAttributes.swift` — must be in BOTH targets (Target Membership)
