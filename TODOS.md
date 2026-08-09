# TODOS

## Home Screen / Live Activity

### Untracked games can show stale "Final" status for hours

**What:** For a game nobody tapped "Track" on, the home screen's Final/Track-button
state depends entirely on `ScheduleStore.games` (the NHL schedule API), which only
refreshes on cold launch or a scenePhase transition to `.active` (5-minute freshness
window, `ScheduleStore.refreshIfStale`). There is no periodic mid-day refresh —
`BackgroundTaskManager` only runs once, at 6am the next day, to pre-fetch tomorrow's
schedule for notifications.

**Why:** If a user opens the app once and leaves it foregrounded (or backgrounds it
without reopening), an untracked game's row can stay stale — potentially still
showing "LIVE" with an enabled Track button — for hours after the game actually
ended. This is the same underlying failure mode as the original bug fixed on
`NelsonBlakeN/home-screen-final-game-state` (a finished game offering to be tracked),
just via schedule lag instead of the old `finishedGames` gap, and it affects the
common case: most rows in a day's list are games the user never explicitly tracked.

**Context:** Investigated during `/review` on the home-screen-final-game-state
branch (2026-08-08). Confirmed by reading the code, not inferred: the only place
this app ever calls `pushType: .channel(...)` is inside
`LiveActivityManager.startActivity()` (`Firepower/LiveActivityManager.swift:601`),
scoped 1:1 to that specific game's `Activity.request()`. There is no standing
"subscribe to my pinned teams' channels" mechanism — so an untracked game gets zero
push signal, confirmed against both the iOS app and the backend (`scheduler.go`
broadcasts to every scheduled game's team channel regardless of whether any device
is listening; receiving is entirely gated by whether *this device* ever started a
Live Activity for *that* game). `GameRowView.didFinish` already falls back
correctly to `game.isFinal` when there's no `finishedGames` record — this isn't a
regression from that branch, it's a pre-existing gap that branch's fix doesn't
reach.

Three directions considered, not yet decided:
- Tighten in-app schedule refresh cadence (e.g. a periodic foreground timer while
  `TodayView` is visible, shorter than the current 5-minute window) — smallest
  change, doesn't touch the "pure APNs subscriber" architecture.
- Subscribe to pinned/favorite teams' channels regardless of tracking, so at least
  pinned teams get push-accurate Final status without an active Live Activity —
  bigger change, touches `CLAUDE.md`'s documented "iOS app is a pure APNs channel
  subscriber" architecture, needs its own design pass (`/office-hours`).
- Leave as-is; the staleness window is bounded by whenever the user next
  foregrounds the app, which for an actively-used app may be acceptable.

**Effort:** M (schedule-refresh-cadence option) to L (channel-subscription-model
option, needs a design doc)
**Priority:** P2
**Depends on:** None
