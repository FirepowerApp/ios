import ActivityKit
import Foundation

// FirepowerActivityAttributes — the Live Activity contract between backend and iOS.
//
// Static data (set at start, never changes for this activity):
//   sport, homeTeam, awayTeam, gameID
//
// Dynamic data (ContentState — updated by every push):
//   scores, xG, gameState string, lastEvent
//
// Wire format: ContentState must match the JSON shape from formatter.go:
//   { "sport":"nhl", "homeTeam":"BOS", ... }
//
// Sport-agnostic from day 1 (EXP-5): adding NBA later is a ContentState swap,
// not an ActivityAttributes redesign.

public struct FirepowerActivityAttributes: ActivityAttributes {

    // MARK: - Static (set at Activity.request time)

    public let sport: String      // "nhl"
    public let homeTeam: String   // "BOS"
    public let awayTeam: String   // "NYR"
    public let gameID: String     // NHL game ID, for deduplication

    public init(sport: String, homeTeam: String, awayTeam: String, gameID: String) {
        self.sport = sport
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.gameID = gameID
    }

    // MARK: - Dynamic (updated by APNs push)

    public struct ContentState: Codable, Hashable, Sendable {
        public var homeScore: Int
        public var awayScore: Int
        public var homeXG: Double
        public var awayXG: Double
        public var gameState: String   // "14:32 left, 2nd period" / "Final"
        public var lastEvent: String?  // "Goal scored" / "Shot blocked" / nil

        // Derived: is the game over?
        public var isEnded: Bool {
            gameState.lowercased() == "final"
        }

        public init(
            homeScore: Int = 0,
            awayScore: Int = 0,
            homeXG: Double = 0,
            awayXG: Double = 0,
            gameState: String = "",
            lastEvent: String? = nil
        ) {
            self.homeScore = homeScore
            self.awayScore = awayScore
            self.homeXG = homeXG
            self.awayXG = awayXG
            self.gameState = gameState
            self.lastEvent = lastEvent
        }

        // MARK: - Sample states (used in Xcode Previews)

        public static let preview = ContentState(
            homeScore: 2,
            awayScore: 1,
            homeXG: 2.4,
            awayXG: 1.8,
            gameState: "14:32 left, 2nd period",
            lastEvent: "Goal scored"
        )

        public static let previewEnded = ContentState(
            homeScore: 4,
            awayScore: 2,
            homeXG: 3.1,
            awayXG: 2.4,
            gameState: "Final",
            lastEvent: "Final"
        )

        public static let previewIntermission = ContentState(
            homeScore: 1,
            awayScore: 1,
            homeXG: 1.2,
            awayXG: 0.9,
            gameState: "Period ended",
            lastEvent: "Period ended"
        )

        public static let previewEmpty = ContentState()
    }
}
