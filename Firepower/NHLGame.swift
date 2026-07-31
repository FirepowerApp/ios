import Foundation

/// How long before scheduled puck drop tracking becomes available. Bounded by
/// Apple's 8-hour Live Activity budget: starting earlier means the activity is
/// system-ended before the game finishes, and shortens the post-game Final
/// window. A free enum (not a LiveActivityManager static) so NHLGame — a
/// Foundation-only model — never reaches into the @MainActor ActivityKit layer.
enum TrackingWindow {
    static let lead: TimeInterval = 4 * 60 * 60
}

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
        NHLGame.isoFormatter.date(from: startTimeUTC)
    }

    private static let isoFormatter = ISO8601DateFormatter()

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

    /// Live games are always trackable. Games with no known start time fail
    /// open (trackable) rather than blocking on missing data.
    func isTrackable(now: Date = .now) -> Bool {
        if isLive { return true }
        guard isUpcoming else { return false }
        guard let start = startDate else { return true }
        return start.timeIntervalSince(now) <= TrackingWindow.lead
    }

    /// Wall-clock time at which tracking opens, for the disabled-button label.
    var trackingOpensAt: Date? {
        startDate.map { $0.addingTimeInterval(-TrackingWindow.lead) }
    }
}
