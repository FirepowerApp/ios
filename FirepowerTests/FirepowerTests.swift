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
