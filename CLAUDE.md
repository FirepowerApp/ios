# Firepower iOS

NHL hockey Live Activity app. Shows scores on the lock screen and Dynamic Island via APNs broadcast push. Includes a daily game list (NHL Stats API), pinned teams, pre-game notifications, and background schedule refresh.

## Planning docs

Planning materials live at `~/Documents/Firepower/planning/`:
- `todos.md` — deferred work with priority
- `test-plan-*.md` — QA test plan
- `backend/` — Go files for the Live Activity notification package (copy to `~/git/Firepower/backend/`)

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
- Backend: Go, at ~/git/Firepower/backend/

## Key files

- `Firepower/` — main app target (TodayView, LiveActivityManager, FirepowerApp, NHLScheduleClient)
- `FirepowerActivityKit/` — widget extension (FirepowerWidget, FirepowerActivityAttributes)
- `FirepowerActivityAttributes.swift` — must be in BOTH targets (Target Membership)
