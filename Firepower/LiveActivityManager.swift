import ActivityKit
import Combine
import FirepowerShared
import Foundation

// LiveActivityManager controls the lifecycle of the Live Activity for the tracked team.
//
// State machine:
//
//   idle ──► starting ──► tracking ──► ended
//     ▲          │            │
//     └──────────┴────────────┘ (via stop() or game-end push)
//
// v1: one team, one activity. Multi-team is v2.

@MainActor
final class LiveActivityManager: ObservableObject {

    @Published private(set) var state: ActivityState = .idle
    @Published private(set) var currentActivity: Activity<FirepowerActivityAttributes>?
    @Published private(set) var pushToken: String?

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

        // Don't start a duplicate for the same game
        if let existing = currentActivity,
           existing.activityState != .ended,
           existing.activityState != .dismissed {
            state = .tracking
            return
        }

        state = .starting

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
            print("LiveActivityManager: activity started with id=\(activity.id) activityState=\(activity.activityState)")
            currentActivity = activity
            state = .tracking

            Task {
                for await s in activity.activityStateUpdates {
                    print("LiveActivityManager: activityState → \(s)")
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

    func stopActivity() async {
        guard let activity = currentActivity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
        pushToken = nil
        state = .idle
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

        if let existing = currentActivity,
           existing.activityState != .ended,
           existing.activityState != .dismissed {
            state = .tracking
            return
        }

        state = .starting

        let attributes = FirepowerActivityAttributes(
            sport: "nhl",
            homeTeam: "BOS",
            awayTeam: "NYR",
            gameID: "debug-0",
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
            currentActivity = activity
            state = .tracking
            print("Debug Live Activity started: \(activity.id)")
        } catch {
            state = .idle
            print("Debug Live Activity failed to start: \(error)")
        }
    }

    /// Drives the debug activity to a new state without APNs.
    func updateDebugState(_ newState: FirepowerActivityAttributes.ContentState) async {
        guard let activity = currentActivity else { return }
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

