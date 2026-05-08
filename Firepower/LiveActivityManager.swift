import ActivityKit
import Combine
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

        let attributes = FirepowerActivityAttributes(
            sport: "nhl",
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            gameID: gameID
        )
        let initialState = FirepowerActivityAttributes.ContentState()

        let content = ActivityContent(
            state: initialState,
            staleDate: Date().addingTimeInterval(90)   // first stale-date; pushes will update this
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            print("LiveActivityManager: activity started with id=\(activity.id) activityState=\(activity.activityState)")
            currentActivity = activity
            state = .tracking

            Task {
                for await s in activity.activityStateUpdates {
                    print("LiveActivityManager: activityState → \(s)")
                }
            }

            // Subscribe to channel token updates (needed for server-side push registration).
            // For broadcast push this is the channel token; for per-device it's the device token.
            Task { await observePushTokenUpdates(activity: activity, teamTricode: homeTeam) }
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
        state = .idle
    }

    // MARK: - Push token / channel observation

    private func observePushTokenUpdates(activity: Activity<FirepowerActivityAttributes>, teamTricode: String) async {
        for await tokenData in activity.pushTokenUpdates {
            let tokenHex = tokenData.map { String(format: "%02x", $0) }.joined()
            print("LiveActivityManager: push token for \(teamTricode): \(tokenHex)")
            // TODO (v1): log the token. The backend uses broadcast push to a static
            // channel ID ("nhl-team-BOS") — for broadcast we don't need to register
            // per-device tokens. Keep this for observability and for when Push-to-Start
            // (v2) requires token registration.
            //
            // For per-device push (non-broadcast fallback), send this token to:
            //   POST /api/v1/teams/{tricode}/register-push-token
            //   body: { "token": tokenHex }
        }
    }
}

