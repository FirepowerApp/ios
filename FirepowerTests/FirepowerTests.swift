//
//  FirepowerTests.swift
//  FirepowerTests
//
//  Created by Blake Nelson on 5/6/26.
//

import Testing
import Foundation
import FirepowerShared
@testable import Firepower

// MARK: - Helpers

/// Builds an absolute Date from an America/New_York wall-clock time.
private func et(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

private func etHour(_ iso: String) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    let instant = ISO8601DateFormatter().date(from: iso)!
    return cal.component(.hour, from: instant)
}

private func game(_ id: Int, start: String, home: String = "BOS", away: String = "NYR",
                  homeScore: Int? = 3, awayScore: Int? = 1, state: String = "OFF",
                  type: Int? = 2) -> NHLGame {
    NHLGame(
        id: id,
        startTimeUTC: start,
        homeTeam: .init(abbrev: home, score: homeScore),
        awayTeam: .init(abbrev: away, score: awayScore),
        gameState: state,
        gameType: type
    )
}

// MARK: - OffseasonReplay.resolveAnchor

// Mirrors the emulator's resolveState: in the summer gap today's response
// describes NEXT season, so the anchor (day after the previous season's
// playoffs) is only reachable by walking previousStartDate back.
@Suite("OffseasonReplay.resolveAnchor")
struct OffseasonReplayResolveAnchorTests {

    typealias B = OffseasonReplay.Boundaries

    // Summer 2026 as the API reports it: today's response rolled forward to
    // the 2026-27 season; one hop back is still that gap's pre-season block,
    // two hops back is the 2025-26 season that actually started and ended.
    private let today = B(regularSeasonStartDate: "2026-10-07", playoffEndDate: "2027-06-20",
                          previousStartDate: "2026-09-01")
    private func fetch(_ date: String) -> B {
        switch date {
        case "2026-09-01": return B(regularSeasonStartDate: "2026-10-07", playoffEndDate: "2027-06-20",
                                    previousStartDate: "2026-06-01")
        case "2026-06-01": return B(regularSeasonStartDate: "2025-10-07", playoffEndDate: "2026-06-14",
                                    previousStartDate: "2026-05-01")
        default: return B()
        }
    }

    @Test("regular season under way: nil, and no walk-back fetches")
    func inSeasonIsNil() async throws {
        var fetches = 0
        let anchor = try await OffseasonReplay.resolveAnchor(
            today: "2026-10-07", current: today) { _ in fetches += 1; return B() }
        #expect(anchor == nil)
        #expect(fetches == 0)
    }

    @Test("offseason: walks back to the season that started; anchor = its playoffEndDate + 1")
    func offseasonAnchorFromPreviousSeason() async throws {
        let anchor = try await OffseasonReplay.resolveAnchor(today: "2026-09-23", current: today) { fetch($0) }
        #expect(anchor == "2026-06-15")
    }

    @Test("API failure propagates so the caller can fall back to regular-season behavior")
    func fetchFailureThrows() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await OffseasonReplay.resolveAnchor(today: "2026-09-23", current: today) { _ in throw Boom() }
        }
    }

    @Test("missing regularSeasonStartDate throws (never guesses)")
    func missingSeasonStartThrows() async {
        await #expect(throws: OffseasonReplay.AnchorError.self) {
            try await OffseasonReplay.resolveAnchor(today: "2026-09-23", current: B()) { _ in B() }
        }
    }

    @Test("no previousStartDate to walk to throws")
    func noPreviousThrows() async {
        let cur = B(regularSeasonStartDate: "2026-10-07", playoffEndDate: nil, previousStartDate: nil)
        await #expect(throws: OffseasonReplay.AnchorError.self) {
            try await OffseasonReplay.resolveAnchor(today: "2026-09-23", current: cur) { _ in B() }
        }
    }

    @Test("walk-back is bounded")
    func walkBackIsBounded() async {
        var fetches = 0
        await #expect(throws: OffseasonReplay.AnchorError.self) {
            try await OffseasonReplay.resolveAnchor(today: "2026-09-23", current: today) { _ in
                fetches += 1
                return B(regularSeasonStartDate: "2999-01-01", playoffEndDate: nil, previousStartDate: "2026-01-01")
            }
        }
        #expect(fetches == OffseasonReplay.maxWalkBack)
    }

    @Test("a previous playoff end that is not before today throws")
    func anchorAfterTodayThrows() async {
        await #expect(throws: OffseasonReplay.AnchorError.self) {
            try await OffseasonReplay.resolveAnchor(today: "2026-06-10", current: today) { fetch($0) }
        }
    }
}

// MARK: - OffseasonReplay.replay (dense index)

@Suite("OffseasonReplay.replay")
struct OffseasonReplayDenseIndexTests {

    // 2025-10-08 has no games: the saved days are dense, the calendar isn't.
    private let days: [OffseasonReplay.SeasonDay] = [
        .init(date: "2025-10-07", games: [game(1, start: "2025-10-07T23:00:00Z")]),
        .init(date: "2025-10-09", games: [game(2, start: "2025-10-09T23:00:00Z")]),
        .init(date: "2025-10-10", games: [game(3, start: "2025-10-10T23:00:00Z")]),
    ]

    @Test("anchor day serves the first saved day")
    func anchorDayIsIndexZero() {
        let r = OffseasonReplay.replay(anchor: "2026-06-15", today: "2026-06-15", days: days)
        #expect(r?.replay.queryDate == "2025-10-07")
        #expect(r?.replay.dayShift == 251)
        #expect(r?.games.map(\.id) == [1])
    }

    @Test("index counts served days, skipping the season's off-days")
    func skipsSeasonOffDays() {
        let r = OffseasonReplay.replay(anchor: "2026-06-15", today: "2026-06-16", days: days)
        #expect(r?.replay.queryDate == "2025-10-09")   // not 2025-10-08
        #expect(r?.replay.dayShift == 250)
        #expect(r?.games.map(\.id) == [2])
    }

    @Test("before the anchor or past the saved season: nil (no games)")
    func outOfRangeIsNil() {
        #expect(OffseasonReplay.replay(anchor: "2026-06-15", today: "2026-06-14", days: days) == nil)
        #expect(OffseasonReplay.replay(anchor: "2026-06-15", today: "2026-06-18", days: days) == nil)
    }

    // "Today" is keyed off whatever time zone is passed in (the device's own
    // zone in production, via the `.current` default) — never a fixed zone.
    // The same instant lands on different calendar dates depending on where
    // the device is, and the UTC/ET columns below must NOT match the local
    // one, or this test isn't actually proving the zone is respected.
    @Test("today is the device's local date, not a fixed UTC or ET date")
    func todayIsLocalDate() {
        let utc = TimeZone(identifier: "UTC")!
        let easternTime = TimeZone(identifier: "America/New_York")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!

        // 2026-09-25 20:00 ET == 2026-09-26 00:00 UTC == 2026-09-26 09:00 JST
        let instant = et(2026, 9, 25, 20, 0)
        #expect(OffseasonReplay.todayString(instant, timeZone: easternTime) == "2026-09-25")
        #expect(OffseasonReplay.todayString(instant, timeZone: utc) == "2026-09-26")
        #expect(OffseasonReplay.todayString(instant, timeZone: tokyo) == "2026-09-26")
    }

    @Test("the bundled season file is the emulator's: 211 game-days from 2025-10-07 to 2026-06-14")
    func embeddedSeasonFile() {
        let d = OffseasonReplay.embeddedDays
        #expect(d.count == 211)
        #expect(d.first?.date == "2025-10-07")
        #expect(d.last?.date == "2026-06-14")
    }
}

// MARK: - OffseasonReplay.reshape

struct OffseasonReplayReshapeTests {

    private let replay = OffseasonReplay(queryDate: "2025-10-07", dayShift: 265)

    @Test func forcesFutAndClearsScores() {
        let out = replay.reshape([game(1, start: "2025-10-08T23:00:00Z")]).first
        #expect(out?.gameState == "FUT")
        #expect(out?.homeTeam.score == nil)
        #expect(out?.awayTeam.score == nil)
    }

    @Test func preservesIdAndType() {
        let out = replay.reshape([game(42, start: "2025-10-08T23:00:00Z", type: 3)]).first
        #expect(out?.id == 42)
        #expect(out?.gameType == 3)
    }

    @Test func shiftsStartTimeByDayShift() {
        // Oct 8 2025 + 265 days = June 30 2026, same ET wall clock.
        let out = replay.reshape([game(1, start: "2025-10-08T23:00:00Z")]).first
        let shifted = ISO8601DateFormatter().date(from: out!.startTimeUTC)!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let comps = cal.dateComponents([.year, .month, .day], from: shifted)
        #expect(comps.year == 2026 && comps.month == 6 && comps.day == 30)
    }

    // CRITICAL: DST-aware. A November (EST) game shifted into summer (EDT) keeps
    // its ET wall-clock time-of-day, not its raw UTC offset.
    @Test func preservesLocalClockAcrossDST() {
        // 2025-11-15T00:00Z == Nov 14, 19:00 EST.
        let replay250 = OffseasonReplay(queryDate: "2025-11-15", dayShift: 250)
        let out = replay250.reshape([game(1, start: "2025-11-15T00:00:00Z")]).first
        // After the shift the ET wall clock is still 19:00 (now EDT).
        #expect(etHour(out!.startTimeUTC) == 19)
    }

    @Test func emptyInEmptyOut() {
        #expect(replay.reshape([]).isEmpty)
    }
}

// MARK: - NHLGame.isTrackable

@Suite("NHLGame.isTrackable")
struct NHLGameTrackableTests {

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func upcoming(startOffset: TimeInterval) -> NHLGame {
        let iso = ISO8601DateFormatter().string(from: now.addingTimeInterval(startOffset))
        return game(1, start: iso, state: "FUT")
    }

    @Test("exactly 4h out is trackable (boundary is inclusive)")
    func exactlyFourHoursOut() {
        let g = upcoming(startOffset: TrackingWindow.lead)
        #expect(g.isTrackable(now: now))
    }

    @Test("4h and one second out is not yet trackable")
    func justOverFourHoursOut() {
        let g = upcoming(startOffset: TrackingWindow.lead + 1)
        #expect(!g.isTrackable(now: now))
    }

    @Test("4h minus one second out is trackable")
    func justUnderFourHoursOut() {
        let g = upcoming(startOffset: TrackingWindow.lead - 1)
        #expect(g.isTrackable(now: now))
    }

    @Test("a live game is always trackable regardless of start time")
    func liveGameAlwaysTrackable() {
        let iso = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600))
        let g = game(1, start: iso, state: "LIVE")
        #expect(g.isTrackable(now: now))
    }

    @Test("a final game is never trackable")
    func finalGameNotTrackable() {
        let iso = ISO8601DateFormatter().string(from: now.addingTimeInterval(-7200))
        let g = game(1, start: iso, state: "OFF")
        #expect(!g.isTrackable(now: now))
    }

    @Test("trackingOpensAt is 4h before scheduled start")
    func trackingOpensAtOffset() {
        let start = now.addingTimeInterval(6 * 3600)
        let iso = ISO8601DateFormatter().string(from: start)
        let g = game(1, start: iso, state: "FUT")
        #expect(g.trackingOpensAt == start.addingTimeInterval(-TrackingWindow.lead))
    }

    @Test("an unparseable start time fails open (trackable, no opensAt)")
    func nilStartDateFailsOpen() {
        let g = game(1, start: "not-a-date", state: "FUT")
        #expect(g.startDate == nil)
        #expect(g.isTrackable(now: now))
        #expect(g.trackingOpensAt == nil)
    }
}

// MARK: - LiveActivityManager.rehydratePlan

// Pure decision-tree tests. Activity<FirepowerActivityAttributes> is a
// non-injectable ActivityKit static that cannot be constructed in a test, so
// rehydrate()'s decision logic is exercised entirely through these value-type
// snapshots — no ActivityKit, no @MainActor isolation, no device needed.
@Suite("LiveActivityManager.rehydratePlan")
struct RehydratePlanTests {

    private typealias Action = LiveActivityManager.RehydrateAction
    private typealias ActivitySnapshot = LiveActivityManager.ActivitySnapshot
    private typealias TrackedSnapshot = LiveActivityManager.TrackedSnapshot

    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private let grace: TimeInterval = 10

    @Test("empty enumeration and empty tracked produce no actions")
    func emptyProducesNoActions() {
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: [], tracked: [], now: now, grace: grace)
        #expect(actions.isEmpty)
    }

    @Test("a live enumerated activity with no tracked entry is adopted")
    func untrackedLiveActivityIsAdopted() {
        let enumerated = [ActivitySnapshot(activityID: "a1", gameID: "g1", isLive: true)]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: [], now: now, grace: grace)
        #expect(actions == [.adopt(gameID: "g1", activityID: "a1")])
    }

    @Test("a not-live enumerated activity is skipped, not adopted")
    func notLiveEnumeratedActivityIsSkipped() {
        let enumerated = [ActivitySnapshot(activityID: "a1", gameID: "g1", isLive: false)]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: [], now: now, grace: grace)
        #expect(actions.isEmpty)
    }

    // REGRESSION: the shipped rehydrate() ended the activity it already owns
    // when called a second time, because its guard matched the SAME activity
    // as a "duplicate". This is the exact case this test locks in.
    @Test("same activity ID enumerated and tracked is kept, never re-adopted")
    func sameActivityIDIsKept() {
        let enumerated = [ActivitySnapshot(activityID: "a1", gameID: "g1", isLive: true)]
        let tracked = [TrackedSnapshot(activityID: "a1", gameID: "g1", isLive: true, adoptedAt: now)]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: tracked, now: now, grace: grace)
        #expect(actions == [.keep(gameID: "g1")])
    }

    // REGRESSION: a naive "different ID → duplicate, end it" rule would end
    // the LIVE enumerated activity here, because the tracked entry (dead) is
    // what the code already "owns". The correct behavior is to prefer the
    // live one and adopt it instead.
    @Test("different activity ID, tracked one dead: adopts the live enumerated one")
    func differentIDTrackedDeadAdoptsLive() {
        let enumerated = [ActivitySnapshot(activityID: "a2", gameID: "g1", isLive: true)]
        let tracked = [TrackedSnapshot(activityID: "a1", gameID: "g1", isLive: false, adoptedAt: now)]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: tracked, now: now, grace: grace)
        #expect(actions == [.adopt(gameID: "g1", activityID: "a2")])
    }

    @Test("different activity ID, tracked one live: ends the duplicate")
    func differentIDTrackedLiveEndsDuplicate() {
        let enumerated = [ActivitySnapshot(activityID: "a2", gameID: "g1", isLive: true)]
        let tracked = [TrackedSnapshot(activityID: "a1", gameID: "g1", isLive: true, adoptedAt: now)]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: tracked, now: now, grace: grace)
        #expect(actions == [.endDuplicate(activityID: "a2")])
    }

    // A user-swiped (.dismissed) activity is removed from the enumeration
    // entirely, so absence is the only signal available. Within the grace
    // period this must NOT be pruned — it might just be a fresh start that
    // the daemon hasn't listed yet.
    @Test("tracked entry absent from enumeration within grace is kept")
    func absentWithinGraceIsKept() {
        let tracked = [TrackedSnapshot(activityID: "a1", gameID: "g1", isLive: true,
                                       adoptedAt: now.addingTimeInterval(-1))]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: [], tracked: tracked, now: now, grace: grace)
        #expect(actions == [.keep(gameID: "g1")])
    }

    @Test("tracked entry absent from enumeration past grace is pruned")
    func absentPastGraceIsPruned() {
        let tracked = [TrackedSnapshot(activityID: "a1", gameID: "g1", isLive: true,
                                       adoptedAt: now.addingTimeInterval(-11))]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: [], tracked: tracked, now: now, grace: grace)
        #expect(actions == [.prune(gameID: "g1")])
    }

    @Test("exactly at the grace boundary is pruned (grace is exclusive)")
    func exactlyAtGraceBoundaryIsPruned() {
        let tracked = [TrackedSnapshot(activityID: "a1", gameID: "g1", isLive: true,
                                       adoptedAt: now.addingTimeInterval(-grace))]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: [], tracked: tracked, now: now, grace: grace)
        #expect(actions == [.prune(gameID: "g1")])
    }

    // REGRESSION (adversarial review, eng finding #1): an activity that
    // reached .ended while STILL enumerable (e.g. the app was backgrounded
    // through the whole game and Apple's own 8h ceiling ended it with no app
    // code in the loop) is treated identically to a genuinely-absent
    // (dismissed) activity — both produce .prune. This is the exact
    // precondition rehydrate()'s .prune handler relies on to capture the
    // game's finishedGames result (from the real held Activity's
    // content.state) before clearing `tracked`. This test locks in that
    // .prune — not .keep, not silently dropped — is still the action here,
    // so a future rehydratePlan change can't quietly break that capture site
    // without a test failing. (The capture itself isn't testable here — it
    // touches the live Activity object, which is why it lives in the
    // ActivityKit-edge handler, not in this pure decision function.)
    @Test("a tracked entry whose enumerated snapshot is already .ended is pruned, not kept or adopted")
    func endedButStillEnumeratedTrackedEntryIsPruned() {
        let enumerated = [ActivitySnapshot(activityID: "a1", gameID: "g1", isLive: false, gameEnded: true)]
        let tracked = [TrackedSnapshot(activityID: "a1", gameID: "g1", isLive: true,
                                       adoptedAt: now.addingTimeInterval(-3600))]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: tracked, now: now, grace: grace)
        #expect(actions == [.prune(gameID: "g1")])
    }

    @Test("two independent games are decided independently in one pass")
    func twoGamesDecidedIndependently() {
        let enumerated = [ActivitySnapshot(activityID: "a1", gameID: "g1", isLive: true)]
        let tracked = [
            TrackedSnapshot(activityID: "a1", gameID: "g1", isLive: true, adoptedAt: now),
            TrackedSnapshot(activityID: "a2", gameID: "g2", isLive: true, adoptedAt: now.addingTimeInterval(-11)),
        ]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: tracked, now: now, grace: grace)
        #expect(Set(actions) == Set([.keep(gameID: "g1"), .prune(gameID: "g2")]))
    }

    // REGRESSION (adversarial review, 2026-07-30): trackedByGameID is built
    // once from the pre-existing `tracked` snapshot and never updated as the
    // loop runs, so two live activities sharing a gameID that are BOTH new to
    // `tracked` — e.g. two lingering activities left over from a pre-fix
    // double-Track, rehydrated for the first time — would each independently
    // see "untracked" and both get adopted, orphaning one activity's
    // observe() loops. The old pre-refactor code caught this by checking an
    // accumulating dictionary each iteration; the pure-function rewrite
    // dropped that until this test forced it back.
    @Test("two live untracked activities sharing a gameID: first is adopted, second is a duplicate")
    func duplicateGameIDBothNewToTrackedOnlyAdoptsFirst() {
        let enumerated = [
            ActivitySnapshot(activityID: "a1", gameID: "g1", isLive: true),
            ActivitySnapshot(activityID: "a2", gameID: "g1", isLive: true),
        ]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: [], now: now, grace: grace)
        #expect(actions == [.adopt(gameID: "g1", activityID: "a1"), .endDuplicate(activityID: "a2")])
    }

    @Test("three live untracked activities sharing a gameID: only the first is adopted")
    func tripleDuplicateGameIDOnlyAdoptsFirst() {
        let enumerated = [
            ActivitySnapshot(activityID: "a1", gameID: "g1", isLive: true),
            ActivitySnapshot(activityID: "a2", gameID: "g1", isLive: true),
            ActivitySnapshot(activityID: "a3", gameID: "g1", isLive: true),
        ]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: [], now: now, grace: grace)
        #expect(actions == [
            .adopt(gameID: "g1", activityID: "a1"),
            .endDuplicate(activityID: "a2"),
            .endDuplicate(activityID: "a3"),
        ])
    }

    @Test("duplicate untracked activities where the first is already Final: endFinal, then duplicate")
    func duplicateGameIDFirstAlreadyFinal() {
        let enumerated = [
            ActivitySnapshot(activityID: "a1", gameID: "g1", isLive: true, gameEnded: true),
            ActivitySnapshot(activityID: "a2", gameID: "g1", isLive: true),
        ]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: [], now: now, grace: grace)
        #expect(actions == [.endFinal(gameID: "g1", activityID: "a1"), .endDuplicate(activityID: "a2")])
    }

    // MARK: - endFinal (the backend never sends event:"end"; the client decides)

    @Test("a live, tracked activity whose content reaches Final is ended, not kept")
    func trackedActivityReachingFinalIsEnded() {
        let enumerated = [ActivitySnapshot(activityID: "a1", gameID: "g1", isLive: true, gameEnded: true)]
        let tracked = [TrackedSnapshot(activityID: "a1", gameID: "g1", isLive: true, adoptedAt: now)]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: tracked, now: now, grace: grace)
        #expect(actions == [.endFinal(gameID: "g1", activityID: "a1")])
    }

    @Test("an untracked activity whose content is already Final is adopted-then-ended, not merely adopted")
    func untrackedActivityAlreadyFinalIsAdoptedThenEnded() {
        // E.g. a cold relaunch long after the game ended: the backend never
        // sent event:"end", so the activity is still enumerable and still
        // .active at the ActivityKit level, but its content already says Final.
        let enumerated = [ActivitySnapshot(activityID: "a1", gameID: "g1", isLive: true, gameEnded: true)]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: [], now: now, grace: grace)
        #expect(actions == [.endFinal(gameID: "g1", activityID: "a1")])
    }

    @Test("replacing a dead tracked entry with an already-Final live one still ends it")
    func replacingDeadEntryWithFinalActivityEndsIt() {
        let enumerated = [ActivitySnapshot(activityID: "a2", gameID: "g1", isLive: true, gameEnded: true)]
        let tracked = [TrackedSnapshot(activityID: "a1", gameID: "g1", isLive: false, adoptedAt: now)]
        let actions = LiveActivityManager.rehydratePlan(
            enumerated: enumerated, tracked: tracked, now: now, grace: grace)
        #expect(actions == [.endFinal(gameID: "g1", activityID: "a2")])
    }

    @Test("gameEnded false (the default) preserves the original keep/adopt behavior")
    func gameEndedFalseIsTheDefault() {
        // Regression guard for the ActivitySnapshot(gameEnded:) default —
        // every pre-existing test above constructs snapshots without passing
        // gameEnded, and must still see keep/adopt, not endFinal.
        let snapshot = ActivitySnapshot(activityID: "a1", gameID: "g1", isLive: true)
        #expect(snapshot.gameEnded == false)
    }
}

// MARK: - ScheduleStore cache

// Scope: reloadCacheIfNewer() and writeCache() are fully testable against an
// injected UserDefaults suite with no network dependency. refreshIfStale()'s
// nil / day-rollover / stale branches all end in a real NHLScheduleClient
// fetch (an all-static struct, not injected — see eng review D6, deferred);
// those remain covered by the design doc's manual criteria 2b/2c/2d. The one
// refreshIfStale branch below needs no network because it returns early.
@MainActor
@Suite("ScheduleStore cache")
struct ScheduleStoreCacheTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "FirepowerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func writeRawCache(games: [NHLGame], date: Date, into defaults: UserDefaults) {
        defaults.set(try! JSONEncoder().encode(games), forKey: ScheduleStore.gamesKey)
        defaults.set(try! JSONEncoder().encode(date), forKey: ScheduleStore.dateKey)
    }

    // The regression this whole test file exists to catch: refresh() used to
    // persist a second, later Date() than the in-memory lastFetchDate, which
    // made every "is the cache newer?" comparison always true.
    @Test("writeCache persists the passed date, not a fresh one")
    func writeCachePersistsPassedDate() {
        let defaults = makeDefaults()
        let past = Date(timeIntervalSince1970: 1_000_000)
        ScheduleStore.writeCache([game(1, start: "2026-07-29T23:00:00Z")], at: past, into: defaults)

        let dateData = defaults.data(forKey: ScheduleStore.dateKey)!
        let decoded = try! JSONDecoder().decode(Date.self, from: dateData)
        #expect(decoded == past)
    }

    @Test("reloadCacheIfNewer no-ops with no cached date at all")
    func noOpWithNoCachedDate() {
        let store = ScheduleStore(defaults: makeDefaults())
        store.reloadCacheIfNewer()
        #expect(store.games.isEmpty)
        #expect(store.lastFetchDate == nil)
    }

    @Test("reloadCacheIfNewer ignores a cache from a different day")
    func ignoresCacheFromDifferentDay() {
        let defaults = makeDefaults()
        let store = ScheduleStore(defaults: defaults)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        writeRawCache(games: [game(1, start: "2026-07-29T23:00:00Z")], date: yesterday, into: defaults)

        store.reloadCacheIfNewer()
        #expect(store.games.isEmpty)
        #expect(store.lastFetchDate == nil)
    }

    @Test("reloadCacheIfNewer adopts when there is no prior in-memory fetch")
    func adoptsWhenLastFetchDateNil() {
        let defaults = makeDefaults()
        let store = ScheduleStore(defaults: defaults)
        #expect(store.lastFetchDate == nil)

        let today = Date()
        writeRawCache(games: [game(7, start: "2026-07-29T23:00:00Z")], date: today, into: defaults)
        store.reloadCacheIfNewer()

        #expect(store.games.first?.id == 7)
        #expect(store.lastFetchDate == today)
    }

    @Test("reloadCacheIfNewer adopts a strictly newer cache")
    func adoptsStrictlyNewerCache() {
        let defaults = makeDefaults()
        let older = Date().addingTimeInterval(-3600)
        writeRawCache(games: [game(1, start: "2026-07-29T23:00:00Z")], date: older, into: defaults)
        let store = ScheduleStore(defaults: defaults) // init's loadCache() adopts the older entry
        #expect(store.lastFetchDate == older)

        let newer = Date()
        writeRawCache(games: [game(2, start: "2026-07-29T23:00:00Z")], date: newer, into: defaults)
        store.reloadCacheIfNewer()

        #expect(store.games.first?.id == 2)
        #expect(store.lastFetchDate == newer)
    }

    // CRITICAL: this is the exact bug. Before the writeCache fix, a fresh
    // Date() minted at persist time was always later than lastFetchDate, so
    // this comparison was always true and the full games array was decoded
    // and reassigned on every single foreground.
    @Test("reloadCacheIfNewer is a no-op when the cache is not strictly newer")
    func noOpWhenCacheNotNewer() {
        let defaults = makeDefaults()
        let now = Date()
        writeRawCache(games: [game(1, start: "2026-07-29T23:00:00Z")], date: now, into: defaults)
        let store = ScheduleStore(defaults: defaults)
        #expect(store.lastFetchDate == now)

        // Same timestamp persisted again — must not be treated as newer.
        writeRawCache(games: [game(2, start: "2026-07-29T23:00:00Z")], date: now, into: defaults)
        store.reloadCacheIfNewer()

        #expect(store.games.first?.id == 1)
    }

    @Test("reloadCacheIfNewer no-ops when the games payload fails to decode")
    func noOpWhenGamesDecodeFails() {
        let defaults = makeDefaults()
        let store = ScheduleStore(defaults: defaults)
        defaults.set(try! JSONEncoder().encode(Date()), forKey: ScheduleStore.dateKey)
        defaults.set(Data([0xFF, 0x00]), forKey: ScheduleStore.gamesKey) // not valid JSON

        store.reloadCacheIfNewer()
        #expect(store.games.isEmpty)
        #expect(store.lastFetchDate == nil)
    }

    @Test("refreshIfStale no-ops within the freshness window (no network call)")
    func refreshIfStaleNoOpWithinWindow() async {
        let defaults = makeDefaults()
        let store = ScheduleStore(defaults: defaults)
        let now = Date()
        writeRawCache(games: [game(1, start: "2026-07-29T23:00:00Z")], date: now, into: defaults)
        store.reloadCacheIfNewer() // seed lastFetchDate = now

        await store.refreshIfStale()

        #expect(store.games.first?.id == 1)
        #expect(store.fetchError == nil)
    }
}

// MARK: - LiveActivityManager.FinishedGame

// Pure decision-tree + I/O-shape tests. Building a real LiveActivityManager
// isn't done here (its init() calls rehydrate(), which touches the
// non-injectable Activity<FirepowerActivityAttributes> ActivityKit static —
// the same reason RehydratePlanTests below stays at the pure static-func
// level rather than exercising the instance). makeFinishedGame/pruneFinished/
// load/writeFinishedGames are all nonisolated static funcs for exactly this
// reason: the decision and persistence logic is fully testable without ever
// constructing the @MainActor ActivityKit-backed class.
@Suite("LiveActivityManager.FinishedGame")
struct FinishedGameTests {

    private typealias FinishedGame = LiveActivityManager.FinishedGame
    private typealias ContentState = FirepowerActivityAttributes.ContentState

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func makeDefaults() -> UserDefaults {
        let suiteName = "FirepowerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: makeFinishedGame

    @Test("a Final content state produces a matching FinishedGame record")
    func finalStateProducesRecord() {
        let state = ContentState(
            homeScore: 4, awayScore: 2, homeXG: 3.1, awayXG: 2.4, gameState: "Final")
        let record = LiveActivityManager.makeFinishedGame(from: state, gameID: "g1", now: now)
        #expect(record == FinishedGame(
            gameID: "g1", homeScore: 4, awayScore: 2, homeXG: 3.1, awayXG: 2.4, finishedAt: now))
    }

    // REGRESSION GUARD: this is the isEnded guard from the eng review's T1 —
    // observe()'s .ended branch fires both when the backend's Final push ends
    // the activity AND when the user taps "Tracking" to stop a still-LIVE
    // game (stopActivity). Without this guard, stopping a live game would
    // write a bogus "final" record for a game that didn't actually finish.
    @Test("a non-Final content state produces no record (guards a manual stop of a live game)")
    func nonFinalStateProducesNoRecord() {
        let state = ContentState(
            homeScore: 1, awayScore: 0, homeXG: 0.5, awayXG: 0.2,
            gameState: "14:32 left, 2nd period")
        #expect(LiveActivityManager.makeFinishedGame(from: state, gameID: "g1", now: now) == nil)
    }

    @Test("the local debug activity never produces a record, even at Final")
    func debugGameProducesNoRecord() {
        let state = ContentState(
            homeScore: 4, awayScore: 2, homeXG: 3.1, awayXG: 2.4, gameState: "Final")
        let record = LiveActivityManager.makeFinishedGame(
            from: state, gameID: LiveActivityManager.debugGameID, now: now)
        #expect(record == nil)
    }

    // MARK: pruneFinished

    @Test("a record from today is kept")
    func pruneKeepsToday() {
        let records = ["g1": FinishedGame(
            gameID: "g1", homeScore: 4, awayScore: 2, homeXG: 3.1, awayXG: 2.4, finishedAt: Date())]
        let pruned = LiveActivityManager.pruneFinished(records, now: Date())
        #expect(pruned["g1"] != nil)
    }

    @Test("a record from yesterday is dropped")
    func pruneDropsYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let records = ["g1": FinishedGame(
            gameID: "g1", homeScore: 4, awayScore: 2, homeXG: 3.1, awayXG: 2.4, finishedAt: yesterday)]
        let pruned = LiveActivityManager.pruneFinished(records, now: Date())
        #expect(pruned["g1"] == nil)
    }

    // Exercises that pruning buckets by the INJECTED calendar's timezone, not
    // the device's — the same day-boundary source ScheduleStore's
    // Calendar.current.isDateInToday relies on, made explicit here since
    // pruneFinished takes the calendar as a parameter.
    @Test("day boundary is evaluated in the injected calendar's timezone")
    func pruneUsesInjectedCalendarTimeZone() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let lateNightET = et(2026, 3, 14, 23, 30)
        let nextDayET = et(2026, 3, 15, 1, 30)
        let records = ["g1": FinishedGame(
            gameID: "g1", homeScore: 4, awayScore: 2, homeXG: 3.1, awayXG: 2.4, finishedAt: lateNightET)]
        let pruned = LiveActivityManager.pruneFinished(records, now: nextDayET, calendar: cal)
        #expect(pruned["g1"] == nil)
    }

    @Test("multiple records are pruned independently")
    func pruneIsIndependentPerRecord() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let records = [
            "g1": FinishedGame(gameID: "g1", homeScore: 4, awayScore: 2, homeXG: 3.1, awayXG: 2.4, finishedAt: Date()),
            "g2": FinishedGame(gameID: "g2", homeScore: 1, awayScore: 0, homeXG: 0.8, awayXG: 0.6, finishedAt: yesterday),
        ]
        let pruned = LiveActivityManager.pruneFinished(records, now: Date())
        #expect(pruned["g1"] != nil)
        #expect(pruned["g2"] == nil)
    }

    // MARK: Codec

    @Test("FinishedGame round-trips through JSON encode/decode preserving all fields")
    func finishedGameCodecRoundTrip() {
        let original = FinishedGame(
            gameID: "g1", homeScore: 4, awayScore: 2, homeXG: 3.1, awayXG: 2.4, finishedAt: now)
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(FinishedGame.self, from: data)
        #expect(decoded == original)
    }

    // MARK: load/writeFinishedGames

    @Test("writeFinishedGames then loadFinishedGames round-trips through UserDefaults")
    func writeThenLoadRoundTrips() {
        let defaults = makeDefaults()
        let records = ["g1": FinishedGame(
            gameID: "g1", homeScore: 4, awayScore: 2, homeXG: 3.1, awayXG: 2.4, finishedAt: Date())]
        LiveActivityManager.writeFinishedGames(records, into: defaults)
        let loaded = LiveActivityManager.loadFinishedGames(from: defaults, now: Date())
        #expect(loaded == records)
    }

    @Test("loadFinishedGames prunes a persisted record from a previous day")
    func loadPrunesStaleRecord() {
        let defaults = makeDefaults()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let records = ["g1": FinishedGame(
            gameID: "g1", homeScore: 4, awayScore: 2, homeXG: 3.1, awayXG: 2.4, finishedAt: yesterday)]
        LiveActivityManager.writeFinishedGames(records, into: defaults)
        let loaded = LiveActivityManager.loadFinishedGames(from: defaults, now: Date())
        #expect(loaded.isEmpty)
    }

    @Test("loadFinishedGames no-ops on no cached data")
    func loadNoOpsWithNoData() {
        let defaults = makeDefaults()
        let loaded = LiveActivityManager.loadFinishedGames(from: defaults, now: Date())
        #expect(loaded.isEmpty)
    }

    @Test("loadFinishedGames no-ops when the payload fails to decode")
    func loadNoOpsOnCorruptData() {
        let defaults = makeDefaults()
        defaults.set(Data([0xFF, 0x00]), forKey: LiveActivityManager.finishedGamesKey)
        let loaded = LiveActivityManager.loadFinishedGames(from: defaults, now: Date())
        #expect(loaded.isEmpty)
    }
}

// MARK: - GameRowView.didFinish

// Pure decision logic, pulled out of the view so the two-signal OR (schedule
// API vs push feed) is tested directly. This is the exact truth table that
// closes the original bug: a stale-LIVE schedule combined with a persisted
// FinishedGame record must still read as finished.
@Suite("GameRowView.didFinish")
struct GameRowViewDidFinishTests {

    @Test("schedule Final, no push record: finished")
    func scheduleFinalOnly() {
        #expect(GameRowView.didFinish(scheduleIsFinal: true, hasFinishedRecord: false))
    }

    @Test("schedule not Final, push record present: finished (the core bug this closes)")
    func pushRecordOnly() {
        #expect(GameRowView.didFinish(scheduleIsFinal: false, hasFinishedRecord: true))
    }

    @Test("schedule Final and push record present: finished")
    func bothSignalsFinal() {
        #expect(GameRowView.didFinish(scheduleIsFinal: true, hasFinishedRecord: true))
    }

    @Test("neither signal Final: not finished")
    func neitherSignalFinal() {
        #expect(!GameRowView.didFinish(scheduleIsFinal: false, hasFinishedRecord: false))
    }
}

// MARK: - GameRowView.resolvedScore

// Testing specialist finding (eng review): the score-resolution fallback that
// makes the persisted push result win over a stale schedule fetch had no
// dedicated test, unlike its sibling didFinish above.
@Suite("GameRowView.resolvedScore")
struct GameRowViewResolvedScoreTests {

    @Test("finished record score wins over schedule score")
    func finishedRecordScoreWins() {
        #expect(GameRowView.resolvedScore(scheduleScore: 1, finishedRecordScore: 5) == 5)
    }

    @Test("falls back to schedule score when no finished record")
    func fallsBackToScheduleScoreWhenNoRecord() {
        #expect(GameRowView.resolvedScore(scheduleScore: 1, finishedRecordScore: nil) == 1)
    }

    @Test("both nil resolves to nil")
    func bothNilResolvesToNil() {
        #expect(GameRowView.resolvedScore(scheduleScore: nil, finishedRecordScore: nil) == nil)
    }
}

// MARK: - BuildEnvironment

// The TestFlight/App-Store split has no Apple-documented API — it's inferred
// from the app-store receipt's filename. Resolution must fail CLOSED toward
// .appStore: a wrong guess should only ever hide the offseason replay data
// from a real user, never expose it. These tests pin that fail-closed
// behavior for every receiptName value other than the one known TestFlight
// signal ("sandboxReceipt").
@Suite("BuildEnvironment.resolve")
struct BuildEnvironmentResolveTests {

    @Test("sandboxReceipt resolves to testFlight")
    func sandboxReceiptIsTestFlight() {
        #expect(BuildEnvironment.resolve(receiptName: "sandboxReceipt") == .testFlight)
    }

    @Test("receipt (App Store's real filename) resolves to appStore")
    func receiptIsAppStore() {
        #expect(BuildEnvironment.resolve(receiptName: "receipt") == .appStore)
    }

    @Test("nil receipt (no receipt at all) fails closed to appStore")
    func nilReceiptFailsClosedToAppStore() {
        #expect(BuildEnvironment.resolve(receiptName: nil) == .appStore)
    }

    @Test("unrecognized receipt name fails closed to appStore")
    func unrecognizedReceiptFailsClosedToAppStore() {
        #expect(BuildEnvironment.resolve(receiptName: "somethingUnexpected") == .appStore)
    }

    @Test("only .dev and .testFlight show replayed games; .appStore never does")
    func showsReplayedGamesGating() {
        #expect(BuildEnvironment.dev.showsReplayedGames)
        #expect(BuildEnvironment.testFlight.showsReplayedGames)
        #expect(!BuildEnvironment.appStore.showsReplayedGames)
    }
}

// MARK: - UserPreferences pinned-team persistence

// Regression coverage for the reboot bug: pinned teams used to vanish after a
// power-off/restart. UserPreferences cached its pins in a snapshot loaded once
// at init; a read before the first unlock after a reboot returned an empty set,
// and the next togglePin persisted that whole empty-derived snapshot, wiping the
// real pins from disk. pinnedTeams is now a cache-free computed passthrough, so
// a stale in-memory view can never clobber the live store.
@Suite("UserPreferences pinned-team persistence")
struct UserPreferencesPinTests {

    private func freshDefaults() -> UserDefaults {
        let name = "UserPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("a second instance reads pins written by the first (no stale cache)")
    func readsAcrossInstances() {
        let defaults = freshDefaults()
        UserPreferences(defaults: defaults).pinnedTeams = ["BOS", "EDM"]
        #expect(UserPreferences(defaults: defaults).pinnedTeams == ["BOS", "EDM"])
    }

    @Test("toggle preserves pins that appear on disk after init (the reboot bug)")
    func togglePreservesLateAppearingPins() {
        let defaults = freshDefaults()
        // Instance created while the store reads empty — models a locked,
        // before-first-unlock background launch.
        let prefs = UserPreferences(defaults: defaults)
        #expect(prefs.pinnedTeams.isEmpty)
        // The real pins become readable later (after first unlock / from disk).
        defaults.set(try! JSONEncoder().encode(["BOS", "EDM"]), forKey: "pinnedTeams")
        // User pins a new team.
        prefs.togglePin("TOR")
        #expect(prefs.pinnedTeams == ["BOS", "EDM", "TOR"])
    }

    @Test("toggling an existing pin removes only that team")
    func toggleOffOne() {
        let defaults = freshDefaults()
        let prefs = UserPreferences(defaults: defaults)
        prefs.pinnedTeams = ["BOS", "EDM", "TOR"]
        prefs.togglePin("EDM")
        #expect(prefs.pinnedTeams == ["BOS", "TOR"])
    }
}
