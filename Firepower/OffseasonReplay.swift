import Foundation

// OffseasonReplay maps the current offseason date onto the corresponding real
// 2025-26 NHL date so the app can show "today's" replayed games.
//
// During the offseason the real NHL schedule (api-web.nhle.com) is empty, so
// there is nothing to start a Live Activity for. FirepowerApp/gameDataEmulator
// replays the completed 2025-26 season shifted forward in the calendar, and the
// backend pushes those updates to the team channels. The app can't reach the
// emulator, but it CAN reach the real NHL API — so it fetches the corresponding
// real 2025-26 date and slides those games onto today.
//
//   real 2025-26 season            shifted "replay" calendar (summer 2026)
//   ───────────────────            ───────────────────────────────────────
//   2025-10-07 (Day 1)   ──+265──► 2026-06-29   (replayDay1)
//                                  2026-06-25..28  pre-roll duplicates of Day 1
//
// Anchors mirror the emulator's cmd/buildschedule flags
// (-day1 2025-10-07 -target-day1 2026-06-29). If the emulator is rebuilt with a
// different anchor, update seasonDay1/replayDay1 here; the pinned test in
// FirepowerTests will flag the drift.
struct OffseasonReplay {

    /// Real NHL date to fetch from api-web.nhle.com ("yyyy-MM-dd").
    let queryDate: String
    /// ET calendar days to slide fetched games forward onto "today".
    let dayShift: Int

    // MARK: - Anchors (2025-26 season → summer-2026 replay)

    static let seasonDay1  = "2025-10-07"  // real 2025-26 opening night
    static let replayDay1  = "2026-06-29"  // shifted Day-1 in the emulator
    static let windowStart = "2026-06-22"  // offseason replay window (inclusive)
    static let windowEnd   = "2026-09-30"  // hard cutoff (matches emulator)

    /// The emulator carries duplicate Day-1 slates on the 4 days before
    /// replayDay1 (June 25-28) using synthetic game IDs that don't exist
    /// upstream. The app maps those days to real Day-1 so they're testable too.
    static let preRollDays = 4

    /// America/New_York — the timezone the NHL (and the emulator) key game dates
    /// in. Using ET, not device-local, keeps the date mapping correct near
    /// midnight and regardless of where the device is.
    static let timeZone = TimeZone(identifier: "America/New_York")!

    // MARK: - Plan

    /// Builds a replay plan for `now`, or nil when `now` is outside the replay
    /// window — in which case the caller uses the normal in-season path.
    static func plan(for now: Date = Date()) -> OffseasonReplay? {
        let cal = calendar
        let today = cal.startOfDay(for: now)

        guard
            let windowStartDate = day(windowStart),
            let windowEndDate   = day(windowEnd),
            today >= windowStartDate, today <= windowEndDate,
            let seasonStart = day(seasonDay1),
            let replayStart = day(replayDay1),
            let offsetDays  = cal.dateComponents([.day], from: seasonStart, to: replayStart).day,
            let preRollStart = cal.date(byAdding: .day, value: -preRollDays, to: replayStart)
        else { return nil }

        // Pre-roll days (June 25-28) replay real Day-1; every other in-window day
        // shifts back by the fixed season offset.
        let realDate: Date
        if today >= preRollStart, today < replayStart {
            realDate = seasonStart
        } else if let shifted = cal.date(byAdding: .day, value: -offsetDays, to: today) {
            realDate = shifted
        } else {
            return nil
        }

        guard let shift = cal.dateComponents([.day], from: realDate, to: today).day else {
            return nil
        }
        return OffseasonReplay(queryDate: string(from: realDate), dayShift: shift)
    }

    // MARK: - Reshape

    /// Slides games from `queryDate` onto today: shifts each start time forward
    /// by `dayShift` ET days (DST-aware, preserving local time-of-day), forces
    /// gameState to FUT, and clears scores.
    ///
    /// FUT is load-bearing, not cosmetic: GameRowView only shows the "Track"
    /// button for upcoming/live games, and clearing scores prevents the real
    /// final score from spoiling the row.
    func reshape(_ games: [NHLGame]) -> [NHLGame] {
        games.map { game in
            var home = game.homeTeam; home.score = nil
            var away = game.awayTeam; away.score = nil
            return NHLGame(
                id: game.id,
                startTimeUTC: Self.shift(game.startTimeUTC, byDays: dayShift) ?? game.startTimeUTC,
                homeTeam: home,
                awayTeam: away,
                gameState: "FUT",
                gameType: game.gameType
            )
        }
    }

    // MARK: - Helpers

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    private static func day(_ string: String) -> Date? {
        dateFormatter.date(from: string).map { calendar.startOfDay(for: $0) }
    }

    private static func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// Shifts an ISO-8601 UTC timestamp forward by `days` ET calendar days,
    /// preserving the local (ET) time-of-day across DST boundaries. Adding day
    /// components through an ET-zoned calendar recomputes the UTC offset for the
    /// resulting date, so a 7 PM EST start stays 7 PM EDT after the shift.
    private static func shift(_ iso: String, byDays days: Int) -> String? {
        guard let instant = isoFormatter.date(from: iso),
              let shifted = calendar.date(byAdding: .day, value: days, to: instant)
        else { return nil }
        return isoFormatter.string(from: shifted)
    }
}
