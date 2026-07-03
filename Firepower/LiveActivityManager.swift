import ActivityKit
import Combine
import FirepowerShared
import Foundation

// LiveActivityManager controls the lifecycle of Live Activities. Users can track
// multiple games at once, so activities are keyed by game ID; each has its own
// APNs channel subscription and lives independently until stopped or ended by a
// game-end push.

@MainActor
final class LiveActivityManager: ObservableObject {

    /// Active Live Activities keyed by NHL game ID. One entry per tracked game.
    @Published private(set) var activities: [String: Activity<FirepowerActivityAttributes>] = [:]
    @Published private(set) var state: ActivityState = .idle
    @Published private(set) var pushToken: String?

    /// Game ID used for the local DEBUG activity.
    static let debugGameID = "debug-0"

    /// Whether the given game currently has a live (non-ended) activity.
    func isTracking(gameID: String) -> Bool {
        guard let activity = activities[gameID] else { return false }
        return activity.activityState != .ended && activity.activityState != .dismissed
    }

    enum ActivityState: Equatable {
        case idle
        case starting
        case tracking
        case ended
        case denied      // Live Activities disabled in Settings
        case unavailable // iOS < 18 or not supported on this device
    }

    // MARK: - Authorization check

    func checkAuthorization() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            state = .denied
            return
        }
        if state == .denied { state = .idle }
    }

    // MARK: - Start

    /// Starts a Live Activity for the given game and subscribes to the team channel.
    /// - Parameters:
    ///   - homeTeam: tricode e.g. "BOS"
    ///   - awayTeam: tricode e.g. "NYR"
    ///   - gameID:   NHL game ID for deduplication
    func startActivity(homeTeam: String, awayTeam: String, gameID: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            state = .denied
            return
        }

        // Don't start a duplicate activity for the same game; other games are
        // unaffected — multiple activities can run at once.
        if isTracking(gameID: gameID) { return }

        // Resolve which team's logo to show in DI minimal.
        // Priority: pinned home > pinned away > home fallback.
        let pinned = UserPreferences.shared.pinnedTeams
        let pinnedTricode: String?
        if pinned.contains(homeTeam)      { pinnedTricode = homeTeam }
        else if pinned.contains(awayTeam) { pinnedTricode = awayTeam }
        else                              { pinnedTricode = nil }

        let attributes = FirepowerActivityAttributes(
            sport: "nhl",
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            gameID: gameID,
            pinnedTricode: pinnedTricode
        )
        let initialState = FirepowerActivityAttributes.ContentState()

        let content = ActivityContent(
            state: initialState,
            staleDate: Date().addingTimeInterval(90)   // first stale-date; pushes will update this
        )

        do {
            // Subscribe to whichever team's channel is configured. The backend
            // broadcasts each game on both teams' channels, so home or away works;
            // prefer home when both are present.
            guard let team = [homeTeam, awayTeam]
                .compactMap({ NHLTeam.team(for: $0) })
                .first(where: { !$0.channelId.isEmpty })
            else {
                print("LiveActivityManager: no channel ID for \(awayTeam)@\(homeTeam)")
                state = .idle
                return
            }

            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .channel(team.channelId)
            )
            print("LiveActivityManager: activity started for game \(gameID) id=\(activity.id) activityState=\(activity.activityState)")
            activities[gameID] = activity
            state = .tracking

            // Drop the activity from the dict when it ends (stop or game-end push)
            // so its row flips back to "Track".
            Task {
                for await s in activity.activityStateUpdates {
                    print("LiveActivityManager: [game \(gameID)] activityState → \(s)")
                    if s == .ended || s == .dismissed {
                        activities[gameID] = nil
                        if activities.isEmpty { state = .idle }
                    }
                }
            }

            // Log push token updates for debugging. The backend delivers via the
            // broadcast channel (nhl-team-{tricode}); no per-device registration needed.
            Task { await logPushTokenUpdates(activity: activity, teamTricode: team.tricode) }
            Task { await logContentStateUpdates(activity: activity, teamTricode: team.tricode) }
        } catch {
            state = .idle
            print("LiveActivityManager: failed to start activity: \(error)")
        }
    }

    // MARK: - Stop

    func stopActivity(gameID: String) async {
        guard let activity = activities[gameID] else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        activities[gameID] = nil
        if activities.isEmpty {
            pushToken = nil
            state = .idle
        }
    }

    // MARK: - Debug (DEBUG builds only)

#if DEBUG
    /// Starts a fake BOS@NYR Live Activity driven by local state updates.
    /// No APNs channel is needed — call updateDebugState() to push new state.
    func startDebugActivity(initialState: FirepowerActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            state = .denied
            return
        }

        if isTracking(gameID: Self.debugGameID) { return }

        state = .starting

        let attributes = FirepowerActivityAttributes(
            sport: "nhl",
            homeTeam: "BOS",
            awayTeam: "NYR",
            gameID: Self.debugGameID,
            pinnedTricode: "BOS"
        )
        let content = ActivityContent(state: initialState, staleDate: Date().addingTimeInterval(3600))

        do {
            // .token works in the simulator and doesn't need the broadcasting
            // entitlement. APNs pushes won't land (no server pushing to us),
            // but Activity.update() drives state changes fine for local testing.
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            activities[Self.debugGameID] = activity
            state = .tracking
            print("Debug Live Activity started: \(activity.id)")
        } catch {
            state = .idle
            print("Debug Live Activity failed to start: \(error)")
        }
    }

    /// Drives the debug activity to a new state without APNs.
    func updateDebugState(_ newState: FirepowerActivityAttributes.ContentState) async {
        guard let activity = activities[Self.debugGameID] else { return }
        let content = ActivityContent(state: newState, staleDate: Date().addingTimeInterval(3600))
        await activity.update(content)
    }
#endif

    // MARK: - Push token logging

    private func logContentStateUpdates(activity: Activity<FirepowerActivityAttributes>, teamTricode: String) async {
        for await state in activity.contentStateUpdates {
            print("LiveActivityManager: [\(teamTricode)] push received ↓")
            print("  score:       \(state.homeScore) – \(state.awayScore)")
            print("  xG:          \(String(format: "%.2f", state.homeXG)) – \(String(format: "%.2f", state.awayXG))")
            print("  gameState:   \(state.gameState)")
            if let type_ = state.eventType   { print("  eventType:   \(type_)") }
            if let detail = state.eventDetail, !detail.isEmpty { print("  eventDetail: \(detail)") }
            if let team   = state.eventTeam  { print("  eventTeam:   \(team)") }
        }
    }

    private func logPushTokenUpdates(activity: Activity<FirepowerActivityAttributes>, teamTricode: String) async {
        for await tokenData in activity.pushTokenUpdates {
            let hex = tokenData.map { String(format: "%02x", $0) }.joined()
            print("LiveActivityManager: channel nhl-team-\(teamTricode) push token: \(hex)")
            pushToken = hex
        }
    }
}

