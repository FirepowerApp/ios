import Foundation

/// Fetches live/final scores directly from the NHL API, independent of the
/// schedule endpoint's embedded (often laggy) score. One batch call per date
/// covers every game that day, keyed by game ID — cheaper and fresher than a
/// per-game boxscore fetch.
struct NHLScoreClient {

    private static let baseURL = "https://api-web.nhle.com"

    struct ScoreEntry {
        let gameID: Int
        let homeScore: Int?
        let awayScore: Int?
        let gameState: String
    }

    static func fetchScores(date: String) async throws -> [Int: ScoreEntry] {
        guard let url = URL(string: "\(baseURL)/v1/score/\(date)") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(ScoreResponse.self, from: data)

        var result: [Int: ScoreEntry] = [:]
        for game in decoded.games {
            result[game.id] = ScoreEntry(
                gameID: game.id,
                homeScore: game.homeTeam.score,
                awayScore: game.awayTeam.score,
                gameState: game.gameState)
        }
        return result
    }
}

// MARK: - Decodable shapes

private struct ScoreResponse: Decodable {
    let games: [ScoreGame]
}

private struct ScoreGame: Decodable {
    let id: Int
    let gameState: String
    let homeTeam: ScoreTeam
    let awayTeam: ScoreTeam
}

private struct ScoreTeam: Decodable {
    let score: Int?
}
