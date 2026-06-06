import ActivityKit
import Foundation

// FirepowerActivityAttributes — the Live Activity contract between backend and iOS.
//
// Static data (set at Activity.request time, never changes for this game):
//   sport, homeTeam, awayTeam, gameID, pinnedTricode
//
// Dynamic data (ContentState — updated by every APNs push):
//   scores, xG, gameState, structured event fields
//
// Wire format: ContentState must match the JSON shape from formatter.go:
//   { "homeScore":2, "awayScore":1, "homeXG":2.4, "awayXG":1.8,
//     "gameState":"14:32 left, 2nd period",
//     "eventType":"goal", "eventDetail":"", "eventTeam":"BOS" }
//
// pinnedTricode is resolved at activity-start from UserPreferences.pinnedTeams
// and is NOT pushed per-update — it is static for the lifetime of the activity.
//
// eventDetail carries the scorer name when the scorer pipeline is live;
// iOS renders a generic "Goal" label when eventDetail is empty (graceful fallback).

public struct FirepowerActivityAttributes: ActivityAttributes {

    // MARK: - Static

    public let sport: String         // "nhl"
    public let homeTeam: String      // "BOS"
    public let awayTeam: String      // "NYR"
    public let gameID: String        // NHL game ID, for deduplication
    public let pinnedTricode: String? // Which team to show in DI minimal (nil → home)

    public init(
        sport: String,
        homeTeam: String,
        awayTeam: String,
        gameID: String,
        pinnedTricode: String? = nil
    ) {
        self.sport = sport
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.gameID = gameID
        self.pinnedTricode = pinnedTricode
    }

    // MARK: - Dynamic

    public struct ContentState: Codable, Hashable, Sendable {
        public var homeScore: Int
        public var awayScore: Int
        public var homeXG: Double
        public var awayXG: Double
        public var gameState: String    // "14:32 left, 2nd period" / "Final"
        public var eventType: String?   // "goal" | "penalty" | "period_end" | nil
        public var eventDetail: String? // scorer name when pipeline is live; nil/empty → generic
        public var eventTeam: String?   // "BOS" | "NYR" | nil — drives left/right alignment

        // Backward compat: old backend (pre-live-activity-event-fields) sends `lastEvent`
        // instead of the structured fields. Decoded silently; not used for display directly.
        // Remove after the new backend has been deployed for at least one release cycle.
        private var lastEvent: String?

        // Derived
        public var isEnded: Bool { gameState.lowercased() == "final" }
        public var isPregame: Bool { gameState.isEmpty }

        // Resolved event type: prefer the new structured field; fall back to lastEvent synthesis.
        // This means the widget shows something on old backend pushes (e.g. "Goal") instead
        // of a blank event line, and will automatically upgrade to the richer display once
        // the new backend is deployed.
        public var resolvedEventType: String? {
            if let type_ = eventType, !type_.isEmpty { return type_ }
            guard let legacy = lastEvent, !legacy.isEmpty else { return nil }
            switch legacy.lowercased() {
            case let s where s.contains("goal"):   return "goal"
            case let s where s.contains("penalty"): return "penalty"
            default: return nil
            }
        }

        public var resolvedEventDetail: String? {
            if let type_ = eventType, !type_.isEmpty { return eventDetail }
            return nil // legacy path: no scorer name, generic label only
        }

        public var resolvedEventTeam: String? {
            if let type_ = eventType, !type_.isEmpty { return eventTeam }
            return nil // legacy path: can't tell which team; widget will left-align
        }

        // Winner tricode for Final state — nil if not ended or tied (shouldn't happen in NHL)
        public func winnerTricode(homeTeam: String, awayTeam: String) -> String? {
            guard isEnded else { return nil }
            if homeScore > awayScore { return homeTeam }
            if awayScore > homeScore { return awayTeam }
            return nil
        }

        public init(
            homeScore: Int = 0,
            awayScore: Int = 0,
            homeXG: Double = 0,
            awayXG: Double = 0,
            gameState: String = "",
            eventType: String? = nil,
            eventDetail: String? = nil,
            eventTeam: String? = nil
        ) {
            self.homeScore = homeScore
            self.awayScore = awayScore
            self.homeXG = homeXG
            self.awayXG = awayXG
            self.gameState = gameState
            self.eventType = eventType
            self.eventDetail = eventDetail
            self.eventTeam = eventTeam
        }

        // MARK: - Sample states (Xcode Previews)

        public static let preview = ContentState(
            homeScore: 2,
            awayScore: 1,
            homeXG: 2.4,
            awayXG: 1.8,
            gameState: "14:32 left, 2nd period",
            eventType: "goal",
            eventDetail: "",      // empty until scorer pipeline lands
            eventTeam: "BOS"
        )

        public static let previewEnded = ContentState(
            homeScore: 4,
            awayScore: 2,
            homeXG: 3.1,
            awayXG: 2.4,
            gameState: "Final",
            eventType: nil,
            eventDetail: nil,
            eventTeam: nil
        )

        public static let previewIntermission = ContentState(
            homeScore: 1,
            awayScore: 1,
            homeXG: 1.2,
            awayXG: 0.9,
            gameState: "Period ended",
            eventType: "period_end",
            eventDetail: nil,
            eventTeam: nil
        )

        public static let previewEmpty = ContentState()
    }
}
