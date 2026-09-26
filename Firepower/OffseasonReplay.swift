import Foundation

// OffseasonReplay mirrors FirepowerApp/gameDataEmulator's game selection so the
// app lists the same games the backend is pushing during the offseason.
//
// From the first day of the offseason until the regular season starts
// (offseason + preseason), the emulator serves a dense stack of the saved
// 2025-26 game-days (season_2025-26.json, identical to the emulator's copy):
//
//   anchor ─ +1d ─ +2d ─ ... ─ regular season starts (stop)
//   gameDays[0]  [1]   [2]
//
// where `anchor` = the day after the PREVIOUS season's playoffs ended, and
// today maps to gameDays[days(anchor → today)] rebased onto today. Dense, so
// the season's off-days never show up as empty replay days.
//
// Nothing here is hardcoded per season: whether we're in the stack and where
// day 0 is both come from the live NHL API (`resolveAnchor`), so the app flips
// to offseason behavior on its own with no new build. If the API can't answer,
// callers fall back to normal regular-season behavior rather than guess.
//
// Callers additionally gate on BuildEnvironment.showsReplayedGames — real App
// Store users never see replayed games regardless of date.
struct OffseasonReplay {

    /// Real date of the saved game-day being replayed ("yyyy-MM-dd"); also the
    /// date to ask `/v1/score` about.
    let queryDate: String
    /// ET calendar days to slide that day's games forward onto "today".
    let dayShift: Int

    /// America/New_York — the timezone the NHL (and the emulator) key game dates
    /// in. Using ET, not device-local, keeps the date mapping correct near
    /// midnight and regardless of where the device is.
    static let timeZone = TimeZone(identifier: "America/New_York")!

    // MARK: - Season file

    /// One saved game-day of the embedded season file.
    struct SeasonDay: Decodable {
        let date: String
        let games: [NHLGame]
    }

    private struct SeasonFile: Decodable { let gameWeek: [SeasonDay] }

    /// The bundled `season_2025-26.json`, date-sorted. Empty (and logged) if the
    /// resource is missing or malformed — callers then show no replayed games.
    static let embeddedDays: [SeasonDay] = {
        guard let url = Bundle.main.url(forResource: "season_2025-26", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SeasonFile.self, from: data)
        else {
            print("OffseasonReplay: embedded season file missing or malformed")
            return []
        }
        return file.gameWeek.sorted { $0.date < $1.date }
    }()

    // MARK: - Anchor

    /// The subset of `/v1/schedule/{date}`'s top-level fields needed to place
    /// today relative to the season.
    struct Boundaries {
        var regularSeasonStartDate: String?
        var playoffEndDate: String?
        var previousStartDate: String?
    }

    enum AnchorError: Error { case missingBoundary, previousSeasonNotFound }

    /// Bounds the previousStartDate walk (the offseason is ~15 weeks).
    static let maxWalkBack = 30

    /// Ports the emulator's `resolveState`. Returns nil when the regular season
    /// (or postseason) is under way — serve normal games — else the anchor
    /// date ("yyyy-MM-dd"): the day after the previous season's playoffs ended.
    ///
    /// `current` is today's schedule response. Its `playoffEndDate` is already
    /// NEXT season's, so the season that just ended is found by walking
    /// `previousStartDate` back (via `fetch`) to a response whose
    /// regularSeasonStartDate is on or before the date queried — a season that
    /// actually started. Throws if the API can't answer; callers fall back to
    /// regular-season behavior.
    static func resolveAnchor(
        today: String,
        current: Boundaries,
        fetch: (String) async throws -> Boundaries
    ) async throws -> String? {
        guard let regularSeasonStart = current.regularSeasonStartDate, !regularSeasonStart.isEmpty
        else { throw AnchorError.missingBoundary }
        if today >= regularSeasonStart { return nil }

        var date = current.previousStartDate
        for _ in 0..<maxWalkBack {
            guard let d = date, !d.isEmpty else { throw AnchorError.previousSeasonNotFound }
            let b = try await fetch(d)
            if let start = b.regularSeasonStartDate, !start.isEmpty, start <= d {
                guard let playoffEnd = b.playoffEndDate.flatMap(Self.day),
                      let anchor = calendar.date(byAdding: .day, value: 1, to: playoffEnd),
                      string(from: anchor) <= today
                else { throw AnchorError.missingBoundary }
                return string(from: anchor)
            }
            date = b.previousStartDate
        }
        throw AnchorError.previousSeasonNotFound
    }

    // MARK: - Selection

    /// Today's replay: the dense game-day at `days(anchor → today)`, plus the
    /// shift that rebases it onto today. Nil when today is before the anchor or
    /// past the saved season — "no games today", same as the emulator.
    static func replay(anchor: String, today: String, days: [SeasonDay] = embeddedDays)
        -> (replay: OffseasonReplay, games: [NHLGame])? {
        guard let anchorDay = day(anchor), let todayDay = day(today),
              let index = calendar.dateComponents([.day], from: anchorDay, to: todayDay).day,
              days.indices.contains(index),
              let baseDay = day(days[index].date),
              let shift = calendar.dateComponents([.day], from: baseDay, to: todayDay).day
        else { return nil }
        return (OffseasonReplay(queryDate: days[index].date, dayShift: shift), days[index].games)
    }

    /// "yyyy-MM-dd" for `now` in the device's local time zone. Per project
    /// policy the client always keys "today" off the device's own clock, never
    /// UTC or any other fixed zone — including here, where the backend's
    /// emulator counts `dayIndex` from `time.Now().UTC()`. That means a device
    /// left on ET can, from ~8 PM to midnight ET, show a different offseason
    /// slate than the one the backend is pushing; that mismatch is accepted
    /// as the cost of never reasoning about "today" in a zone the user isn't
    /// actually in. `timeZone` defaults to `.current` and is only a parameter
    /// so tests can pin it without depending on the machine's local zone.
    static func todayString(_ now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: now)
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
