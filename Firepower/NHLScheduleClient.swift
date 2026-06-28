import Foundation

struct NHLScheduleClient {

    private static let baseURL = "https://api-web.nhle.com"

    static func fetchTodayGames() async throws -> [NHLGame] {
        // During the offseason window, map today onto the corresponding real
        // 2025-26 date so replayed games appear. Outside the window `replay` is
        // nil and this behaves exactly as the normal in-season path.
        let replay = OffseasonReplay.plan()
        let dateString = replay?.queryDate ?? todayString()
        guard let url = URL(string: "\(baseURL)/v1/schedule/\(dateString)") else {
            throw URLError(.badURL)
        }

        print("NHLScheduleClient: fetching \(url)\(replay != nil ? " [offseason replay]" : "")")
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

        // The API returns a week block; find the entry whose date matches today.
        // Fall back to gameWeek[0] if no exact match (handles UTC date edge cases).
        let dayEntry = decoded.gameWeek.first(where: { $0.date == dateString })
                    ?? decoded.gameWeek.first

        let games = dayEntry?.games ?? []
        print("NHLScheduleClient: found \(games.count) game(s) for \(dateString)")

        // Filter out preseason (1) and all-star (4); pass unknown gameType through.
        let filtered = games.filter { g in
            guard let type = g.gameType else { return true }
            return type == 2 || type == 3
        }

        // Offseason replay: slide the real 2025-26 games onto today (FUT, scores
        // cleared, start times shifted). No-op on the normal in-season path.
        if let replay {
            return replay.reshape(filtered)
        }
        return filtered
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
}

// MARK: - Decodable shapes

private struct ScheduleResponse: Decodable {
    let gameWeek: [GameWeekEntry]
}

private struct GameWeekEntry: Decodable {
    let date: String
    let games: [NHLGame]
}
