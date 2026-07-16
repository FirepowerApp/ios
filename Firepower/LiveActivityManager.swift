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

    /// True once iOS rejects a start for exceeding its Live Activity cap. The UI
    /// disables the Track button while set. Cleared when a slot frees up (an
    /// activity is stopped or ends), so the cap is learned at runtime rather than
    /// hardcoded — iOS doesn't expose the exact number.
    @Published private(set) var atActivityLimit = false

    /// Game ID used for the local DEBUG activity.
    static let debugGameID = "debug-0"

    /// Max Live Activities to run at once. iOS enforces its own cap (observed at
    /// 5); we stop at the same number so Track disables before a start would fail.
    static let maxConcurrentActivities = 5

    /// At the concurrent-activity cap — either our hardcoded max or an OS
    /// rejection (which covers iOS lowering the limit under memory pressure).
    var isAtCapacity: Bool {
        activities.count >= Self.maxConcurrentActivities || atActivityLimit
    }

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

    init() {
        rehydrate()
    }

    // MARK: - Rehydration

    /// Re-adopts Live Activities that are still running system-side. Activities
    /// outlive the app process (iOS routinely kills the app in the background),
    /// but this dictionary doesn't — without rehydration a relaunch shows every
    /// tracked game as untracked, double-starts activities, miscounts the cap,
    /// and can't stop the orphans.
    private func rehydrate() {
        for activity in Activity<FirepowerActivityAttributes>.activities {
            guard activity.activityState != .ended, activity.activityState != .dismissed else { continue }
            let gameID = activity.attributes.gameID

            // Two live activities for one game is always a bug (pre-rehydration
            // double-Track); keep the first and end the extra.
            guard activities[gameID] == nil else {
                print("LiveActivityManager: ending duplicate activity for game \(gameID) id=\(activity.id)")
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                continue
            }

            activities[gameID] = activity
            observe(activity, gameID: gameID, teamTricode: logTricode(for: activity.attributes))
            print("LiveActivityManager: rehydrated activity for game \(gameID) id=\(activity.id) activityState=\(activity.activityState)")
        }
        if !activities.isEmpty { state = .tracking }
    }

    /// Which team's tricode to use in log lines — mirrors the channel pick in
    /// startActivity (home preferred).
    private func logTricode(for attributes: FirepowerActivityAttributes) -> String {
        [attributes.homeTeam, attributes.awayTeam]
            .compactMap { NHLTeam.team(for: $0) }
            .first(where: { !$0.channelId.isEmpty })?.tricode ?? attributes.homeTeam
    }

    /// Watches an activity's lifecycle (freeing its slot on end/dismiss) and
    /// attaches the debug log streams. Used for both fresh starts and rehydration.
    private func observe(_ activity: Activity<FirepowerActivityAttributes>, gameID: String, teamTricode: String) {
        Task {
            for await s in activity.activityStateUpdates {
                print("LiveActivityManager: [game \(gameID)] activityState → \(s)")
                if s == .ended || s == .dismissed {
                    // Only clear the slot if this instance still owns it — an
                    // ended duplicate must not evict the survivor.
                    if activities[gameID]?.id == activity.id {
                        activities[gameID] = nil
                        atActivityLimit = false  // a slot freed up
                        if activities.isEmpty { state = .idle }
                    }
                }
            }
        }
        Task { await logPushTokenUpdates(activity: activity, teamTricode: teamTricode) }
        Task { await logContentStateUpdates(activity: activity, teamTricode: teamTricode) }
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
    ///   - homeTeam:  tricode e.g. "BOS"
    ///   - awayTeam:  tricode e.g. "NYR"
    ///   - gameID:    NHL game ID for deduplication
    ///   - startTime: scheduled puck drop; shown in the activity until it passes
    func startActivity(homeTeam: String, awayTeam: String, gameID: String, startTime: Date? = nil) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            state = .denied
            return
        }

        // Don't start a duplicate activity for the same game; other games are
        // unaffected — multiple activities can run at once.
        if isTracking(gameID: gameID) { return }

        // Respect the concurrent cap. The UI disables Track here, but guard
        // deep-link / notification starts too.
        if activities.count >= Self.maxConcurrentActivities { return }

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
            pinnedTricode: pinnedTricode,
            startTime: startTime
        )
        let initialState = FirepowerActivityAttributes.ContentState()

        // First stale-date; pushes will update it. For a pregame start, stale at
        // puck drop — that re-render is what flips the widget from the scheduled
        // time ("6:00 PM") to "Pregame" (see ContentState.clockLabel). Otherwise
        // the usual 90s window applies.
        let firstStaleDate: Date
        if let startTime, startTime > Date() {
            firstStaleDate = startTime
        } else {
            firstStaleDate = Date().addingTimeInterval(90)
        }
        let content = ActivityContent(state: initialState, staleDate: firstStaleDate)

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
            atActivityLimit = false  // a start succeeded, so we're under the cap
            observe(activity, gameID: gameID, teamTricode: team.tricode)
        } catch {
            state = activities.isEmpty ? .idle : .tracking
            // The OS cap is the only failure we can recover from by freeing a
            // slot; flag it so the UI disables further Track buttons.
            if let authError = error as? ActivityAuthorizationError {
                switch authError {
                case .targetMaximumExceeded, .globalMaximumExceeded:
                    atActivityLimit = true
                default:
                    break
                }
            }
            print("LiveActivityManager: failed to start activity: \(error)")
        }
    }

    // MARK: - Stop

    func stopActivity(gameID: String) async {
        guard let activity = activities[gameID] else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        activities[gameID] = nil
        atActivityLimit = false  // stopping frees a slot, so re-enable Track
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

