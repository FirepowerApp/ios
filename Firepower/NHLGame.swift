import Foundation

struct NHLGame: Identifiable, Codable {
    let id: Int
    let startTimeUTC: String
    let homeTeam: GameTeam
    let awayTeam: GameTeam
    let gameState: String   // "FUT", "PRE", "LIVE", "CRIT", "OVER", "FINAL", "OFF"
    let gameType: Int?      // 1=preseason, 2=regular, 3=playoffs (optional — missing on some entries)

    struct GameTeam: Codable {
        let abbrev: String
        var score: Int?
    }

    var startDate: Date? {
        ISO8601DateFormatter().date(from: startTimeUTC)
    }

    var formattedStartTime: String {
        guard let date = startDate else { return "TBD" }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        f.timeZone = .current
        return f.string(from: date)
    }

    var isLive: Bool    { gameState == "LIVE" || gameState == "CRIT" }
    var isFinal: Bool   { gameState == "FINAL" || gameState == "OFF" || gameState == "OVER" }
    var isUpcoming: Bool { gameState == "FUT" || gameState == "PRE" }

    var displayState: String {
        if isLive  { return "LIVE" }
        if isFinal { return "Final" }
        return formattedStartTime
    }

    func involves(tricode: String) -> Bool {
        homeTeam.abbrev == tricode || awayTeam.abbrev == tricode
    }

    func pinnedTricode(from pinned: Set<String>) -> String? {
        [homeTeam.abbrev, awayTeam.abbrev].first { pinned.contains($0) }
    }
}
