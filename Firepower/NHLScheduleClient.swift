import Foundation

struct NHLScheduleClient {

    private static let baseURL = "https://api-web.nhle.com"

    /// Fetches today's games. Two independent rules, each keyed off exactly
    /// one condition:
    ///   - SCORE always comes from a direct `/v1/score` lookup by game ID,
    ///     unconditionally — in-season or offseason, any build. This is what
    ///     fixes the schedule endpoint's laggy embedded score, and is exactly
    ///     as true during offseason replay (a spoiler final score showing up
    ///     early is expected there).
    ///   - STATE depends only on whether today is in-season or offseason —
    ///     never on build environment. In-season, state comes from that same
    ///     direct fetch (freshness fix). Offseason, state is never touched by
    ///     any NHL fetch — it's driven purely by `reshape()`'s forced "FUT"
    ///     plus the existing time/tracking/push logic (TrackingWindow,
    ///     isTrackable, LiveActivityManager's isTracking, finishedRecord).
    ///     The direct fetch's state there describes the real, long-finished
    ///     historical game, which is irrelevant to the replayed timeline.
    ///
    /// Offseason means the NHL API says the regular season hasn't started yet
    /// (see `OffseasonReplay.resolveAnchor`); games then come from the bundled
    /// season file, exactly as the emulator selects them. If that can't be
    /// determined (API failure) we fall back to the normal path so a transient
    /// error never shows the wrong games.
    ///
    /// `env` only gates whether offseason replay happens at all
    /// (`showsReplayedGames`) — real App Store users never see fake games,
    /// regardless of date, and never pay for the anchor lookup.
    static func fetchTodayGames(env: BuildEnvironment = .current) async throws -> [NHLGame] {
        let todayStr = todayString()
        let response = try await fetchSchedule(dateString: todayStr)

        if env.showsReplayedGames, let anchor = await offseasonAnchor(response) {
            print("NHLScheduleClient: offseason replay active, anchor \(anchor)")
            guard let selection = OffseasonReplay.replay(anchor: anchor, today: OffseasonReplay.todayString()) else {
                return []  // before the anchor or past the saved season: no games today
            }
            let reshaped = selection.replay.reshape(filterGameTypes(selection.games))

            // Offseason: score always overlaid; state never is — reshape()'s "FUT"
            // plus the existing trackability/push logic stays fully in control.
            return await mergeDirectScores(into: reshaped, dateString: selection.replay.queryDate, applyState: false)
        }

        // Normal in-season path — or offseason on a build that must never show
        // replayed games (App Store production), or an undeterminable season
        // state. In-season: state does come from the direct fetch.
        let todayEntry = response.gameWeek.first(where: { $0.date == todayStr }) ?? response.gameWeek.first
        let filtered = filterGameTypes(todayEntry?.games ?? [])
        return await mergeDirectScores(into: filtered, dateString: todayStr, applyState: true)
    }

    // MARK: - Offseason anchor

    /// Anchor date if the API says the regular season hasn't started, nil if it
    /// has — or if the API can't answer (fail toward regular-season behavior).
    /// The anchor only depends on the season that just ended, so it's reused
    /// while the upcoming regularSeasonStartDate is unchanged, skipping the
    /// previousStartDate walk on every refresh.
    private static func offseasonAnchor(_ response: ScheduleResponse) async -> String? {
        let today = OffseasonReplay.todayString()
        let current = response.boundaries
        if let start = current.regularSeasonStartDate, today < start,
           let cached = await anchorCache.anchor(forSeasonStart: start) {
            return cached
        }
        do {
            let anchor = try await OffseasonReplay.resolveAnchor(today: today, current: current) { date in
                try await fetchSchedule(dateString: date).boundaries
            }
            if let anchor, let start = current.regularSeasonStartDate {
                await anchorCache.store(anchor, forSeasonStart: start)
            }
            return anchor
        } catch {
            print("NHLScheduleClient: could not resolve season state, using regular-season behavior: \(error)")
            return nil
        }
    }

    // ponytail: in-memory only, so a cold launch re-walks once; persist to UserDefaults if that matters.
    private static let anchorCache = AnchorCache()

    private actor AnchorCache {
        private var entry: (seasonStart: String, anchor: String)?
        func anchor(forSeasonStart start: String) -> String? {
            entry?.seasonStart == start ? entry?.anchor : nil
        }
        func store(_ anchor: String, forSeasonStart start: String) {
            entry = (start, anchor)
        }
    }

    static func todayString() -> String {
        dateFormatter.string(from: Date())
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    // MARK: - Fetch helpers

    private static func fetchSchedule(dateString: String) async throws -> ScheduleResponse {
        guard let url = URL(string: "\(baseURL)/v1/schedule/\(dateString)") else {
            throw URLError(.badURL)
        }

        print("NHLScheduleClient: fetching \(url)")
        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse {
            print("NHLScheduleClient: HTTP \(http.statusCode)")
        }

        // Log raw JSON in debug builds to diagnose structure mismatches
        #if DEBUG
        if let raw = String(data: data, encoding: .utf8) {
            print("NHLScheduleClient: raw response (first 2000 chars):")
            print(String(raw.prefix(2000)))
        }
        #endif

        let decoded = try JSONDecoder().decode(ScheduleResponse.self, from: data)
        print("NHLScheduleClient: gameWeek entries = \(decoded.gameWeek.count)")
        return decoded
    }

    // Filter out preseason (1) and all-star (4); pass unknown gameType through.
    private static func filterGameTypes(_ games: [NHLGame]) -> [NHLGame] {
        games.filter { g in
            guard let type = g.gameType else { return true }
            return type == 2 || type == 3
        }
    }

    /// Overlays each game's score with a direct `/v1/score/{date}` lookup by
    /// game ID — always. Best-effort: a failed score fetch leaves `games`
    /// unchanged rather than failing the whole schedule fetch, since the
    /// schedule's own embedded score is still a usable (if laggier) fallback.
    ///
    /// `applyState` is the one knob, and it tracks a single real-world
    /// condition — is today in-season or offseason — not build environment.
    /// True applies the same fetch's gameState too (the in-season freshness
    /// fix). False leaves state untouched (offseason: the fetch's state
    /// describes the real, already-finished historical game, which has
    /// nothing to do with the replayed timeline's own FUT/LIVE/Final).
    private static func mergeDirectScores(
        into games: [NHLGame], dateString: String, applyState: Bool
    ) async -> [NHLGame] {
        guard let scores = try? await NHLScoreClient.fetchScores(date: dateString) else { return games }
        return games.map { game in
            guard let entry = scores[game.id] else { return game }
            var home = game.homeTeam; home.score = entry.homeScore ?? home.score
            var away = game.awayTeam; away.score = entry.awayScore ?? away.score
            return NHLGame(
                id: game.id,
                startTimeUTC: game.startTimeUTC,
                homeTeam: home,
                awayTeam: away,
                gameState: (applyState && !entry.gameState.isEmpty) ? entry.gameState : game.gameState,
                gameType: game.gameType)
        }
    }
}

// MARK: - Decodable shapes

private struct ScheduleResponse: Decodable {
    let gameWeek: [GameWeekEntry]
    let regularSeasonStartDate: String?
    let playoffEndDate: String?
    let previousStartDate: String?

    var boundaries: OffseasonReplay.Boundaries {
        .init(regularSeasonStartDate: regularSeasonStartDate,
              playoffEndDate: playoffEndDate,
              previousStartDate: previousStartDate)
    }
}

private struct GameWeekEntry: Decodable {
    let date: String
    let games: [NHLGame]
}
