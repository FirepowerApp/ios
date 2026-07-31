//
//  FirepowerTests.swift
//  FirepowerTests
//
//  Created by Blake Nelson on 5/6/26.
//

import Testing
import Foundation
@testable import Firepower

// MARK: - Helpers

/// Builds an absolute Date from an America/New_York wall-clock time. ET, not
/// device-local, is what OffseasonReplay buckets by.
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

// MARK: - OffseasonReplay.plan

struct OffseasonReplayPlanTests {

    // CRITICAL: anchor pin. Day-1 of the replay maps to real opening night with
    // the full season offset. Fails loudly if the emulator anchor drifts.
    @Test func anchorDayMapsToRealDay1() {
        let plan = OffseasonReplay.plan(for: et(2026, 6, 29))
        #expect(plan?.queryDate == "2025-10-07")
        #expect(plan?.dayShift == 265)
    }

    // CRITICAL: pre-roll days (June 25-28) replay real Day-1, shifted onto today.
    @Test func preRollDaysMapToRealDay1OntoToday() {
        // June 27 → fetch Oct 7, slide onto June 27 (265 - 2 days).
        let jun27 = OffseasonReplay.plan(for: et(2026, 6, 27))
        #expect(jun27?.queryDate == "2025-10-07")
        #expect(jun27?.dayShift == 263)

        // Boundaries of the pre-roll window.
        #expect(OffseasonReplay.plan(for: et(2026, 6, 25))?.queryDate == "2025-10-07")
        #expect(OffseasonReplay.plan(for: et(2026, 6, 25))?.dayShift == 261)
        #expect(OffseasonReplay.plan(for: et(2026, 6, 28))?.queryDate == "2025-10-07")
        #expect(OffseasonReplay.plan(for: et(2026, 6, 28))?.dayShift == 264)
    }

    // In-window but before pre-roll: normal offset (real date has no games, which
    // is fine — empty list, not a special case).
    @Test func earlyWindowUsesNormalOffset() {
        let jun24 = OffseasonReplay.plan(for: et(2026, 6, 24))
        #expect(jun24?.queryDate == "2025-10-02") // Oct 7 - 5
        #expect(jun24?.dayShift == 265)
    }

    // A mid-season replay date maps back the full offset.
    @Test func midSeasonDateMapsByOffset() {
        // July 13 2026 is 14 days after replayDay1 → real Oct 21 2025.
        let jul13 = OffseasonReplay.plan(for: et(2026, 7, 13))
        #expect(jul13?.queryDate == "2025-10-21")
        #expect(jul13?.dayShift == 265)
    }

    @Test func windowEdgesAreInclusive() {
        #expect(OffseasonReplay.plan(for: et(2026, 6, 22)) != nil)
        #expect(OffseasonReplay.plan(for: et(2026, 9, 30)) != nil)
    }

    // Out of window → nil → caller uses the normal in-season path unchanged.
    @Test func outOfWindowReturnsNil() {
        #expect(OffseasonReplay.plan(for: et(2026, 6, 21)) == nil) // day before window
        #expect(OffseasonReplay.plan(for: et(2026, 10, 1)) == nil) // day after cutoff
        #expect(OffseasonReplay.plan(for: et(2026, 1, 15)) == nil) // deep winter
        #expect(OffseasonReplay.plan(for: et(2026, 12, 25)) == nil)
    }

    // Anchors pin to 2026; a future summer must not silently replay the wrong
    // season against the real NHL API.
    @Test func futureYearReturnsNil() {
        #expect(OffseasonReplay.plan(for: et(2027, 7, 15)) == nil)
    }

    // ET, not device-local: an instant just past ET midnight is "today" in ET.
    @Test func bucketingUsesEasternTime() {
        // 2026-06-29 00:30 ET is still June 29 in ET → anchor day.
        #expect(OffseasonReplay.plan(for: et(2026, 6, 29, 0, 30))?.queryDate == "2025-10-07")
        // 2026-06-28 23:30 ET is June 28 in ET → pre-roll, not June 29.
        #expect(OffseasonReplay.plan(for: et(2026, 6, 28, 23, 30))?.dayShift == 264)
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
