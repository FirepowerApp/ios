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

- v1: BOS hardcoded, TestFlight-only, manual Start Tracking button
- Live Activity starts successfully (state=active, Dynamic Island working)
- Push token obtained with pushType: .token
- Lock screen display: under investigation (see checkpoint for details)
- Backend push: not yet wired up end-to-end

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
