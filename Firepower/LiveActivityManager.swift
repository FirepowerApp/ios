import ActivityKit
import Combine
import FirepowerShared
import Foundation

// LiveActivityManager controls the lifecycle of Live Activities. Users can track
// multiple games at once, so activities are keyed by game ID; each has its own
// APNs channel subscription and lives independently until stopped or ended by
// this app itself.
//
// The backend NEVER sends event:"end". A push with event:"end" is applied by
// the OS directly with no app code in the loop (channel pushes don't require
// the app to be running at all — see CLAUDE.md), which would foreclose any
// chance for this app to decide the dismissal timing. Instead the backend
// always sends event:"update", including on the final push (gameState=Final,
// a long stale-date, but the activity stays alive). Ending it — and choosing
// how long "Final" stays visible — is entirely this app's job. See endIfFinal.
//
// Rehydration lifecycle — who clears a tracked entry, and why absence (not
// state) is the prune signal:
//
//                       Activity.request()
//                              │
//                              ▼
//    ┌──────────────────── .active ────────────────────┐
//    │                        │                        │
//    │  user taps Tracking    │  backend Final push     │  8h budget exhausted
//    │        │               │  (event:"update",        │  (nobody ended it
//    │        ▼               │   content isEnded)       │   in time)
//    │  stopActivity()        │        │                │        │
//    │  clears tracked[id] ───┼─┐      ▼                │        ▼
//    │                        │ │  endIfFinal() ─────────┼──►  .ended
//    │                        │ │  (live contentState     │        │
//    │                        │ │   observer, if the      │        │
//    │                        │ │   app is foregrounded;  │        │
//    │                        │ │   else rehydrate()'s    │        │
//    │                        │ │   .endFinal action on   │        │
//    │                        │ │   next foreground)      │        │
//    │                        │ │      │                 │        │
//    │                        └─┴──►  .ended  ◄───────────┼────────┘
//    │                                  │
//    │                                  └──► observe() handler clears tracked[id]
//    │
//    │   user swipes card
//    │        │
//    │        ▼
//    │   .dismissed ──► REMOVED FROM Activity<>.activities ENTIRELY
//    │        │                        │
//    │        │   process alive ───────┴──► observe() handler clears it
//    │        │
//    │        └── process was suspended (observe()'s task died with it)
//    │                     │
//    │                     ▼
//    └──────────  rehydrate()'s prune, on next foreground
//                 Absence is the ONLY signal here — a dismissed activity is not
//                 enumerated, so state-based pruning would never fire. Hence the
//                 grace period: absence also means "requested seconds ago and
//                 not yet registered with the daemon."

@MainActor
final class LiveActivityManager: ObservableObject {

    /// A tracked activity plus when we adopted it. The timestamp lives with the
    /// activity (rather than in a parallel dictionary) so it is impossible to
    /// track an activity without one — a missing timestamp would otherwise
    /// silently disable the rehydrate prune's grace period.
    struct Tracked {
        let activity: Activity<FirepowerActivityAttributes>
        let adoptedAt: Date
    }

    /// Active Live Activities keyed by NHL game ID. One entry per tracked game.
    @Published private(set) var tracked: [String: Tracked] = [:]
    @Published private(set) var state: ActivityState = .idle
    @Published private(set) var pushToken: String?

    /// Final result captured from the push the moment a tracked game reaches
    /// Final — keyed by NHL game ID. Populated in `observe()`'s `.ended` branch,
    /// BEFORE `tracked[gameID]` is cleared, so the home screen still has the
    /// game's result after the manager forgets it as "tracked". Persisted so it
    /// survives relaunch and outlives the Live Activity itself (which can be
    /// dismissed while the game result is still relevant to the day's list).
    @Published private(set) var finishedGames: [String: FinishedGame] = [:]

    /// True once iOS rejects a start for exceeding its Live Activity cap. The UI
    /// disables the Track button while set. Cleared when a slot frees up (an
    /// activity is stopped or ends), so the cap is learned at runtime rather than
    /// hardcoded — iOS doesn't expose the exact number.
    @Published private(set) var atActivityLimit = false

    /// A completed game's result, captured from the push that reached Final.
    /// Persisted keyed by NHL game ID so the home screen can show a finished
    /// game's real score/xG without re-deriving it from the (possibly stale)
    /// schedule API. Day-scoped: pruned once `finishedAt` is no longer today,
    /// matching ScheduleStore's own day-boundary cache invalidation — a
    /// finished-game record never outlives the single-day list it decorates.
    struct FinishedGame: Codable, Equatable {
        let gameID: String
        let homeScore: Int
        let awayScore: Int
        let homeXG: Double
        let awayXG: Double
        let finishedAt: Date
    }

    static let finishedGamesKey = "finishedGames"

    private let defaults: UserDefaults

    /// Game ID used for the local DEBUG activity.
    static let debugGameID = "debug-0"

    /// Max Live Activities to run at once. iOS enforces its own cap (observed at
    /// 5); we stop at the same number so Track disables before a start would fail.
    static let maxConcurrentActivities = 5

    /// How long a just-adopted entry is protected from the rehydrate prune, in
    /// case Activity<>.activities hasn't enumerated it yet (Activity.request
    /// returning is not documented to be synchronous with daemon registration).
    static let pruneGrace: TimeInterval = 10

    /// How long "Final" stays visible once WE end the activity. Apple clamps
    /// the post-end lock-screen window to 4h regardless of what's requested
    /// (ActivityUIDismissalPolicy.after(_:)) — this constant IS that ceiling,
    /// not a tunable choice.
    static let finalVisibleDuration: TimeInterval = 4 * 60 * 60

    /// At the concurrent-activity cap — either our hardcoded max or an OS
    /// rejection (which covers iOS lowering the limit under memory pressure).
    var isAtCapacity: Bool {
        tracked.count >= Self.maxConcurrentActivities || atActivityLimit
    }

    /// Whether the given game currently has a live (non-ended) activity.
    func isTracking(gameID: String) -> Bool {
        guard let entry = tracked[gameID] else { return false }
        return entry.activity.activityState != .ended && entry.activity.activityState != .dismissed
    }

    enum ActivityState: Equatable {
        case idle
        case starting
        case tracking
        case ended
        case denied      // Live Activities disabled in Settings
        case unavailable // iOS < 18 or not supported on this device
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        finishedGames = Self.loadFinishedGames(from: defaults, now: Date())
        rehydrate()
    }

    // MARK: - Finished-game persistence (pure — no ActivityKit, no I/O)

    /// Builds a `FinishedGame` from a push's content state — nil if the game
    /// hasn't actually reached Final, or it's the local DEBUG activity (which
    /// has no real result worth persisting).
    nonisolated static func makeFinishedGame(
        from state: FirepowerActivityAttributes.ContentState,
        gameID: String,
        now: Date
    ) -> FinishedGame? {
        guard state.isEnded, gameID != debugGameID else { return nil }
        return FinishedGame(
            gameID: gameID,
            homeScore: state.homeScore,
            awayScore: state.awayScore,
            homeXG: state.homeXG,
            awayXG: state.awayXG,
            finishedAt: now
        )
    }

    /// Drops any record whose result isn't from today — mirrors
    /// `ScheduleStore`'s own `Calendar.current.isDateInToday` day-boundary
    /// check, so a finished-game record can never outlive the single-day game
    /// list it decorates.
    nonisolated static func pruneFinished(
        _ records: [String: FinishedGame],
        now: Date,
        calendar: Calendar = .current
    ) -> [String: FinishedGame] {
        records.filter { calendar.isDate($0.value.finishedAt, inSameDayAs: now) }
    }

    /// The single reader of the on-disk finished-games format (mirrors
    /// `ScheduleStore.writeCache`'s "one place knows the shape" role) — pure
    /// I/O + the same prune every write path applies, so a record from a
    /// previous day never surfaces on load either.
    nonisolated static func loadFinishedGames(from defaults: UserDefaults, now: Date) -> [String: FinishedGame] {
        guard let data = defaults.data(forKey: finishedGamesKey),
              let decoded = try? JSONDecoder().decode([String: FinishedGame].self, from: data)
        else { return [:] }
        return pruneFinished(decoded, now: now)
    }

    /// The single writer of the on-disk finished-games format.
    nonisolated static func writeFinishedGames(_ records: [String: FinishedGame], into defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(records) else {
            print("LiveActivityManager: FAILED to encode finishedGames")
            return
        }
        defaults.set(data, forKey: finishedGamesKey)
    }

    private func persistFinishedGames() {
        Self.writeFinishedGames(finishedGames, into: defaults)
    }

    /// Re-applies the day-scope prune. Called from `rehydrate()`, which already
    /// runs on init and on every foreground, so a day boundary crossed while
    /// backgrounded is caught the same way stale schedule data is.
    private func pruneFinishedGamesIfStale() {
        let pruned = Self.pruneFinished(finishedGames, now: Date())
        if pruned.count != finishedGames.count {
            finishedGames = pruned
            persistFinishedGames()
        }
    }

    // MARK: - Rehydration decision (pure — no ActivityKit, no clock, no I/O)

    enum RehydrateAction: Hashable {
        case keep(gameID: String)
        case adopt(gameID: String, activityID: String)
        case endFinal(gameID: String, activityID: String)
        case endDuplicate(activityID: String)
        case prune(gameID: String)
    }

    struct ActivitySnapshot: Equatable {
        let activityID: String
        let gameID: String
        let isLive: Bool     // activityState is neither .ended nor .dismissed
        let gameEnded: Bool  // the pushed ContentState reached Final (content.state.isEnded)

        init(activityID: String, gameID: String, isLive: Bool, gameEnded: Bool = false) {
            self.activityID = activityID
            self.gameID = gameID
            self.isLive = isLive
            self.gameEnded = gameEnded
        }
    }

    struct TrackedSnapshot: Equatable {
        let activityID: String
        let gameID: String
        let isLive: Bool
        let adoptedAt: Date
    }

    /// Decides what to do with each tracked/enumerated activity:
    ///
    ///   for each enumerated (live) activity:
    ///     untracked, content not yet Final ......... adopt
    ///     untracked, content already Final ......... endFinal (adopt, then end —
    ///                                                  e.g. a cold relaunch long
    ///                                                  after the game ended)
    ///     tracked, same activityID, not Final ...... keep (never re-observe)
    ///     tracked, same activityID, now Final ...... endFinal
    ///     tracked, other ID, tracked one is dead ... adopt or endFinal per the
    ///                                                  same not-Final/Final split
    ///                                                  (prefer the live one —
    ///                                                  ending the WRONG one here
    ///                                                  would destroy the only
    ///                                                  live activity)
    ///     tracked, other ID, tracked one is live ... endDuplicate
    ///     two enumerated snapshots share a gameID .. first one claims it (per
    ///                                                  the rules above), every
    ///                                                  later one is endDuplicate
    ///                                                  regardless of what
    ///                                                  `tracked` said going in
    ///
    ///   for each tracked entry absent from the enumeration:
    ///     adoptedAt within `grace` of `now` ......... keep (just started; daemon
    ///                                                  may not list it yet)
    ///     otherwise ................................. prune (catches user swipes,
    ///                                                  which remove the activity
    ///                                                  from the enumeration
    ///                                                  entirely — this is the
    ///                                                  ONLY path that catches them)
    nonisolated static func rehydratePlan(
        enumerated: [ActivitySnapshot],
        tracked: [TrackedSnapshot],
        now: Date,
        grace: TimeInterval
    ) -> [RehydrateAction] {
        var actions: [RehydrateAction] = []
        var handledGameIDs = Set<String>()
        let trackedByGameID = Dictionary(uniqueKeysWithValues: tracked.map { ($0.gameID, $0) })

        // Which activityID has been claimed as the owner for each gameID
        // WITHIN this pass. trackedByGameID alone isn't enough: it reflects
        // state from BEFORE this call, so two live activities sharing a
        // gameID that are BOTH new to `tracked` (e.g. two lingering
        // activities left over from a pre-fix double-Track, rehydrated for
        // the first time) would otherwise each independently see "untracked"
        // and both get adopted — orphaning one activity's observe() loops and
        // undercounting the real concurrency usage.
        var claimedActivityID: [String: String] = [:]

        func takeOwnership(gameID: String, snapshot: ActivitySnapshot) -> RehydrateAction {
            claimedActivityID[gameID] = snapshot.activityID
            return snapshot.gameEnded
                ? .endFinal(gameID: gameID, activityID: snapshot.activityID)
                : .adopt(gameID: gameID, activityID: snapshot.activityID)
        }

        for snapshot in enumerated {
            guard snapshot.isLive else { continue }
            let gameID = snapshot.gameID

            if let claimed = claimedActivityID[gameID], claimed != snapshot.activityID {
                actions.append(.endDuplicate(activityID: snapshot.activityID))
                continue
            }

            handledGameIDs.insert(gameID)

            guard let existing = trackedByGameID[gameID] else {
                actions.append(takeOwnership(gameID: gameID, snapshot: snapshot))
                continue
            }

            if existing.activityID == snapshot.activityID {
                claimedActivityID[gameID] = snapshot.activityID
                actions.append(
                    snapshot.gameEnded
                        ? .endFinal(gameID: gameID, activityID: snapshot.activityID)
                        : .keep(gameID: gameID)
                )
            } else if !existing.isLive {
                // What we hold is dead; prefer the live enumerated one instead
                // of ending it — ending it here would destroy a live activity.
                actions.append(takeOwnership(gameID: gameID, snapshot: snapshot))
            } else {
                actions.append(.endDuplicate(activityID: snapshot.activityID))
            }
        }

        for entry in tracked where !handledGameIDs.contains(entry.gameID) {
            if now.timeIntervalSince(entry.adoptedAt) < grace {
                actions.append(.keep(gameID: entry.gameID))
            } else {
                actions.append(.prune(gameID: entry.gameID))
            }
        }

        return actions
    }

    // MARK: - Rehydration (ActivityKit at the edges; decision above)

    /// Re-adopts Live Activities that are still running system-side and prunes
    /// ones that are gone. Called from init() and from every foreground
    /// reconcile — must stay idempotent, since the previous implementation
    /// re-observing an already-adopted activity would leak three infinite
    /// `for await` loops per call.
    func rehydrate() {
        pruneFinishedGamesIfStale()

        let enumerated = Activity<FirepowerActivityAttributes>.activities.map {
            ActivitySnapshot(
                activityID: $0.id,
                gameID: $0.attributes.gameID,
                isLive: $0.activityState != .ended && $0.activityState != .dismissed,
                gameEnded: $0.content.state.isEnded
            )
        }
        let trackedSnapshots = tracked.map { gameID, entry in
            TrackedSnapshot(
                activityID: entry.activity.id,
                gameID: gameID,
                isLive: entry.activity.activityState != .ended && entry.activity.activityState != .dismissed,
                adoptedAt: entry.adoptedAt
            )
        }

        let actions = Self.rehydratePlan(
            enumerated: enumerated, tracked: trackedSnapshots,
            now: Date(), grace: Self.pruneGrace
        )

        var freedSlot = false
        for action in actions {
            switch action {
            case .keep:
                break

            case .adopt(let gameID, let activityID):
                guard let activity = Activity<FirepowerActivityAttributes>.activities
                    .first(where: { $0.id == activityID }) else { continue }
                adopt(activity, gameID: gameID)
                print("LiveActivityManager: rehydrated activity for game \(gameID) id=\(activityID) activityState=\(activity.activityState)")

            case .endFinal(let gameID, let activityID):
                guard let activity = Activity<FirepowerActivityAttributes>.activities
                    .first(where: { $0.id == activityID }) else { continue }
                // Adopt only if we don't already own it — re-adopting would
                // re-observe() an already-observed activity, the exact leak
                // the identity check elsewhere in this function exists to avoid.
                if tracked[gameID]?.activity.id != activityID {
                    adopt(activity, gameID: gameID)
                }
                Task { await endIfFinal(activity) }

            case .endDuplicate(let activityID):
                guard let activity = Activity<FirepowerActivityAttributes>.activities
                    .first(where: { $0.id == activityID }) else { continue }
                print("LiveActivityManager: ending duplicate activity id=\(activityID)")
                Task { await activity.end(nil, dismissalPolicy: .immediate) }

            case .prune(let gameID):
                // Capture before clearing: this is the ONLY path that catches
                // an activity that reached Final while nobody's process was
                // alive to observe() it live — e.g. the app was backgrounded
                // through the whole game and Apple's own 8h ceiling ended it
                // with no app code in the loop. rehydratePlan's enumeration
                // loop skips already-.ended snapshots (isLive == false) before
                // they're ever handled, so by the time an entry reaches this
                // prune case, this is the last chance to read its content —
                // `tracked[gameID]?.activity` is still the real, held Activity
                // reference, whose `.content.state` reflects the last known
                // push regardless of whether the OS still considers it live.
                if let activity = tracked[gameID]?.activity,
                   let record = Self.makeFinishedGame(from: activity.content.state, gameID: gameID, now: Date()) {
                    finishedGames[gameID] = record
                    persistFinishedGames()
                }
                tracked[gameID] = nil
                freedSlot = true
            }
        }

        // Only clear the runtime-learned OS cap when a slot actually freed —
        // clearing it unconditionally would discard a real
        // .targetMaximumExceeded / .globalMaximumExceeded signal.
        if freedSlot { atActivityLimit = false }

        // Never clobber .denied, which checkAuthorization() sets immediately
        // before this call in TodayView's reconcile().
        if state != .denied {
            state = tracked.isEmpty ? .idle : .tracking
        }
    }

    private func adopt(_ activity: Activity<FirepowerActivityAttributes>, gameID: String) {
        tracked[gameID] = Tracked(activity: activity, adoptedAt: Date())
        observe(activity, gameID: gameID, teamTricode: logTricode(for: activity.attributes))
    }

    /// Ends `activity` with a flat `finalVisibleDuration` dismissal window the
    /// moment its content reaches Final — unless it's already ended/dismissed.
    /// The backend never sends event:"end" (see the header comment), so this
    /// is the one place in the whole pipeline that decides when a finished
    /// game's Live Activity actually goes away.
    ///
    /// Called from two places, covering the two ways the app can learn a game
    /// finished:
    ///   - the live content-state observer below, for the common case where
    ///     the app is foregrounded (or was backgrounded, not killed) when the
    ///     Final push lands — reacts within moments.
    ///   - rehydrate()'s .endFinal action, as the backstop for when the app
    ///     process wasn't running at all — activity.content.state already
    ///     reflects the OS-applied Final push regardless, so the very next
    ///     foreground catches it even if no async loop ever saw it live.
    private func endIfFinal(_ activity: Activity<FirepowerActivityAttributes>) async {
        guard activity.content.state.isEnded,
              activity.activityState != .ended,
              activity.activityState != .dismissed else { return }
        // Logged only once the guard confirms THIS call is the one actually
        // ending it — two call sites both invoke endIfFinal for the same
        // activity, and logging before this guard would misattribute credit
        // if the other one already won the race.
        print("LiveActivityManager: game \(activity.attributes.gameID) reached Final, ending activity id=\(activity.id)")
        await activity.end(nil, dismissalPolicy: .after(Date().addingTimeInterval(Self.finalVisibleDuration)))
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
                    if tracked[gameID]?.activity.id == activity.id {
                        // Capture the game's result BEFORE clearing `tracked` —
                        // this is the one place a finished game's score/xG
                        // survives past the moment the manager stops
                        // considering it "tracked". Guarded on isEnded (inside
                        // makeFinishedGame) so manually stopping a LIVE game via
                        // stopActivity() never writes a bogus "final" record for
                        // a game that didn't actually finish.
                        if let record = Self.makeFinishedGame(
                            from: activity.content.state, gameID: gameID, now: Date()
                        ) {
                            finishedGames[gameID] = record
                            persistFinishedGames()
                        }
                        tracked[gameID] = nil
                        atActivityLimit = false  // a slot freed up
                        if tracked.isEmpty { state = .idle }
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
        if tracked.count >= Self.maxConcurrentActivities { return }

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
            tracked[gameID] = Tracked(activity: activity, adoptedAt: Date())
            state = .tracking
            atActivityLimit = false  // a start succeeded, so we're under the cap
            observe(activity, gameID: gameID, teamTricode: team.tricode)
        } catch {
            state = tracked.isEmpty ? .idle : .tracking
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
        guard let entry = tracked[gameID] else { return }
        await entry.activity.end(nil, dismissalPolicy: .immediate)
        // Capture BEFORE clearing tracked, deterministically — not via
        // observe()'s async .ended branch. That branch guards on
        // tracked[gameID]?.activity.id == activity.id, and this function
        // clears tracked[gameID] synchronously right below with no
        // intervening await, so a genuine Final reached moments before the
        // user tapped "stop tracking" would otherwise lose the race and never
        // get captured.
        if let record = Self.makeFinishedGame(from: entry.activity.content.state, gameID: gameID, now: Date()) {
            finishedGames[gameID] = record
            persistFinishedGames()
        }
        tracked[gameID] = nil
        atActivityLimit = false  // stopping frees a slot, so re-enable Track
        if tracked.isEmpty {
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
            tracked[Self.debugGameID] = Tracked(activity: activity, adoptedAt: Date())
            state = .tracking
            print("Debug Live Activity started: \(activity.id)")
        } catch {
            state = .idle
            print("Debug Live Activity failed to start: \(error)")
        }
    }

    /// Drives the debug activity to a new state without APNs.
    func updateDebugState(_ newState: FirepowerActivityAttributes.ContentState) async {
        guard let entry = tracked[Self.debugGameID] else { return }
        let content = ActivityContent(state: newState, staleDate: Date().addingTimeInterval(3600))
        await entry.activity.update(content)
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

            // Fast path: end it the moment Final arrives while this loop is
            // alive to see it. rehydrate()'s .endFinal action is the backstop
            // for when it wasn't.
            if state.isEnded {
                await endIfFinal(activity)
            }
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
