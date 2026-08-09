import ActivityKit
import FirepowerShared
import SwiftUI

// Set by the "Release-TricodeOnly" build configuration's Active Compilation
// Condition (Firepower target) — an archive built from that configuration ships
// with team-color badges everywhere instead of the licensed logo assets. See
// Firepower.xcodeproj build settings and the Firepower-TricodeOnly scheme.
#if TRICODE_ONLY_BUILD
private let tricodeOnlyBuild = true
#else
private let tricodeOnlyBuild = false
#endif

struct GameRowView: View {

    let game: NHLGame
    @ObservedObject var activityManager: LiveActivityManager
    @ObservedObject var prefs: UserPreferences

    /// Driven by TodayView's TimelineView tick so the 4-hour Track gate opens
    /// without the user relaunching or pulling to refresh.
    var now: Date = .now

    /// Preview/testing-only override to force the team-color fallback badge even
    /// when the real logo asset is present — simulates a build configuration where
    /// TeamLogos.xcassets is excluded (see the App Store build-exclusion plan).
    var forceLogoFallback: Bool = false

    @State private var isStarting = false

    private var homeTeam: NHLTeam? { NHLTeam.team(for: game.homeTeam.abbrev) }
    private var awayTeam: NHLTeam? { NHLTeam.team(for: game.awayTeam.abbrev) }

    private var isTracking: Bool {
        activityManager.isTracking(gameID: String(game.id))
    }

    /// The game's result as captured from the push that reached Final — nil if
    /// this game was never tracked, or was tracked but its finished record has
    /// since been pruned (not from today). Authoritative over the schedule API
    /// when present: it's push-sourced, so it can't lag the way `game.gameState`
    /// can (see LiveActivityManager's finishedGames doc comment).
    private var finishedRecord: LiveActivityManager.FinishedGame? {
        activityManager.finishedGames[String(game.id)]
    }

    /// True once the game is over by EITHER signal — the schedule API
    /// (`game.isFinal`) or the push feed (`finishedRecord`). The push feed is
    /// checked because it updates the instant the backend broadcasts Final,
    /// while the schedule can still read LIVE for a while after — that gap is
    /// exactly what let the Track button stay enabled on a finished game.
    private var didFinish: Bool {
        Self.didFinish(scheduleIsFinal: game.isFinal, hasFinishedRecord: finishedRecord != nil)
    }

    /// Pulled out of `didFinish` as a pure static func so the two-signal OR is
    /// unit-tested directly. True the moment EITHER signal says the game is
    /// over — the schedule API (`game.isFinal`) or the push feed (a persisted
    /// `FinishedGame`). The push feed can be true while the schedule still
    /// reads LIVE; that disagreement window is the bug this exists to close.
    static func didFinish(scheduleIsFinal: Bool, hasFinishedRecord: Bool) -> Bool {
        scheduleIsFinal || hasFinishedRecord
    }

    private var homeScore: Int? { Self.resolvedScore(scheduleScore: game.homeTeam.score, finishedRecordScore: finishedRecord?.homeScore) }
    private var awayScore: Int? { Self.resolvedScore(scheduleScore: game.awayTeam.score, finishedRecordScore: finishedRecord?.awayScore) }

    /// Pulled out for the same reason as `didFinish`: the persisted push
    /// result wins over the (possibly stale) schedule score whenever present.
    static func resolvedScore(scheduleScore: Int?, finishedRecordScore: Int?) -> Int? {
        finishedRecordScore ?? scheduleScore
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Teams column
                VStack(alignment: .leading, spacing: 6) {
                    teamRow(tricode: game.awayTeam.abbrev, score: awayScore, xG: finishedRecord?.awayXG)
                    Text("@")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                    teamRow(tricode: game.homeTeam.abbrev, score: homeScore, xG: finishedRecord?.homeXG)
                }

                Spacer()

                // State / action column
                VStack(alignment: .trailing, spacing: 8) {
                    stateLabel
                    // didFinish first: a finished game never offers Track, even
                    // when game.isUpcoming/isLive still reads true off a stale
                    // schedule fetch — that disagreement is the bug this gates.
                    if !didFinish, game.isUpcoming || game.isLive {
                        trackButton
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Sub-views

    // xG only ever comes from the push, so `xG` is only ever non-nil for a game
    // we actually tracked to Final — never for in-progress/upcoming rows, and
    // never derived from the schedule API alone.
    private func teamRow(tricode: String, score: Int?, xG: Double? = nil) -> some View {
        HStack(spacing: 8) {
            teamImage(tricode: tricode)

            // Team name, not tricode — the tricode already appears inside the logo
            // (or its fallback badge), so repeating it here read as "PIT PIT".
            Text(NHLTeam.team(for: tricode)?.shortName ?? tricode)
                .font(.system(.body, design: .rounded).weight(.semibold))

            if let score = score {
                Text("\(score)")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(!didFinish && game.isLive ? .primary : .secondary)
            }

            if let xG = xG {
                Text("(xG: \(String(format: "%.2f", xG)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func teamImage(tricode: String) -> some View {
        let name = tricode.lowercased()
        if !forceLogoFallback, !DebugFlags.forceTricodeFallback, !tricodeOnlyBuild, UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
        } else {
            TeamTricodeBadge(
                tricode: tricode,
                homeTricode: game.homeTeam.abbrev,
                awayTricode: game.awayTeam.abbrev,
                size: 32
            )
        }
    }

    @ViewBuilder
    private var stateLabel: some View {
        if didFinish {
            // Checked before game.isLive: a finished record can arrive while the
            // schedule API still reads LIVE, and a red "LIVE" pill next to a
            // score that no longer has a Track button would be its own
            // half-fixed version of the original bug.
            Text("Final")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if game.isLive {
            Text("LIVE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red)
                .clipShape(Capsule())
        } else {
            Text(game.displayState)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trackButton: some View {
        if isTracking {
            Button {
                Task { await activityManager.stopActivity(gameID: String(game.id)) }
            } label: {
                Label("Tracking", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
        } else if isStarting {
            Label("Starting…", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            // Trackable if either team has a channel — the backend broadcasts each
            // game on both teams' channels, so home vs away doesn't matter here.
            let hasChannel = homeTeam?.channelId.isEmpty == false
                          || awayTeam?.channelId.isEmpty == false
            // Tracking opens TrackingWindow.lead before puck drop — starting
            // earlier means the Live Activity is system-ended (Apple's 8h cap)
            // before the game finishes.
            let isTrackable = game.isTrackable(now: now)
            // Disable Track once we're at the Live Activity cap; stopping a game
            // frees a slot and re-enables it.
            let canStart = hasChannel && isTrackable && !activityManager.isAtCapacity

            Button {
                guard canStart else { return }
                Task {
                    isStarting = true
                    defer { isStarting = false }
                    await activityManager.startActivity(
                        homeTeam: game.homeTeam.abbrev,
                        awayTeam: game.awayTeam.abbrev,
                        gameID: String(game.id),
                        startTime: game.startDate
                    )
                }
            } label: {
                Text(trackLabel(hasChannel: hasChannel, isTrackable: isTrackable))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(canStart ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(canStart ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                    .clipShape(Capsule())
            }
            .disabled(!canStart)
        }
    }

    // Priority order matches the button state table in the design doc: no
    // feed beats too-early beats at-capacity.
    private func trackLabel(hasChannel: Bool, isTrackable: Bool) -> String {
        guard hasChannel else { return "No feed" }
        guard isTrackable else {
            guard let opensAt = game.trackingOpensAt else { return "Track" }
            return "Track at \(opensAt.formatted(date: .omitted, time: .shortened))"
        }
        return "Track"
    }
}

// MARK: - Previews

#Preview("Game list — real logos") {
    VStack(spacing: 12) {
        GameRowView(
            game: NHLGame(id: 1, startTimeUTC: "2026-08-06T23:00:00Z",
                          homeTeam: .init(abbrev: "BOS"), awayTeam: .init(abbrev: "NYR"),
                          gameState: "FUT", gameType: 2),
            activityManager: LiveActivityManager(), prefs: UserPreferences.shared
        )
        GameRowView(
            game: NHLGame(id: 2, startTimeUTC: "2026-08-06T23:00:00Z",
                          homeTeam: .init(abbrev: "DET"), awayTeam: .init(abbrev: "CHI"),
                          gameState: "FUT", gameType: 2),
            activityManager: LiveActivityManager(), prefs: UserPreferences.shared
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

// Simulates a build where TeamLogos.xcassets is excluded (App Store submission
// without licensed crest assets) — every row falls back to the team-color badge.
// Includes known collision pairs (BOS/PIT gold, NYR/NYI blue, DET/CHI red) to verify
// the fallback badge's collision resolution reads the same as the lock screen badge.
#Preview("Game list — fallback badges (logos excluded)") {
    VStack(spacing: 12) {
        GameRowView(
            game: NHLGame(id: 1, startTimeUTC: "2026-08-06T23:00:00Z",
                          homeTeam: .init(abbrev: "BOS"), awayTeam: .init(abbrev: "NYR"),
                          gameState: "FUT", gameType: 2),
            activityManager: LiveActivityManager(), prefs: UserPreferences.shared,
            forceLogoFallback: true
        )
        GameRowView(
            game: NHLGame(id: 2, startTimeUTC: "2026-08-06T23:00:00Z",
                          homeTeam: .init(abbrev: "PIT"), awayTeam: .init(abbrev: "NYI"),
                          gameState: "FUT", gameType: 2),
            activityManager: LiveActivityManager(), prefs: UserPreferences.shared,
            forceLogoFallback: true
        )
        GameRowView(
            game: NHLGame(id: 3, startTimeUTC: "2026-08-06T23:00:00Z",
                          homeTeam: .init(abbrev: "DET"), awayTeam: .init(abbrev: "CHI"),
                          gameState: "FUT", gameType: 2),
            activityManager: LiveActivityManager(), prefs: UserPreferences.shared,
            forceLogoFallback: true
        )
        GameRowView(
            game: NHLGame(id: 4, startTimeUTC: "2026-08-06T23:00:00Z",
                          homeTeam: .init(abbrev: "EDM"), awayTeam: .init(abbrev: "VAN"),
                          gameState: "FUT", gameType: 2),
            activityManager: LiveActivityManager(), prefs: UserPreferences.shared,
            forceLogoFallback: true
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

// MARK: - Previews (finished games)

// Seeds a LiveActivityManager's finishedGames via the same injectable-UserDefaults
// path FirepowerTests uses (LiveActivityManager.writeFinishedGames /
// init(defaults:)) — no real ActivityKit push needed to populate a result.
private func previewManager(finished: [String: LiveActivityManager.FinishedGame]) -> LiveActivityManager {
    let suiteName = "GameRowView-Preview-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    LiveActivityManager.writeFinishedGames(finished, into: defaults)
    return LiveActivityManager(defaults: defaults)
}

#Preview("Finished game — normal xG") {
    let game = NHLGame(id: 101, startTimeUTC: "2026-08-06T23:00:00Z",
                        homeTeam: .init(abbrev: "BOS", score: 4), awayTeam: .init(abbrev: "NYR", score: 2),
                        gameState: "OFF", gameType: 2)
    let record = LiveActivityManager.FinishedGame(
        gameID: "101", homeScore: 4, awayScore: 2, homeXG: 3.1, awayXG: 2.4, finishedAt: Date())
    GameRowView(game: game, activityManager: previewManager(finished: ["101": record]), prefs: UserPreferences.shared)
        .padding()
        .background(Color(.systemGroupedBackground))
}

// THE BUG THIS BRANCH FIXES: the schedule API still reads LIVE (a stale
// fetch), but the push already delivered Final. Before the fix, this row
// showed an enabled Track button on a decided game — didFinish now wins on
// the push signal alone, so the row shows the persisted result instead.
#Preview("Finished game — schedule stuck on stale LIVE (the bug this fixes)") {
    let game = NHLGame(id: 102, startTimeUTC: "2026-08-06T23:00:00Z",
                        homeTeam: .init(abbrev: "TOR", score: 1), awayTeam: .init(abbrev: "MTL", score: 1),
                        gameState: "LIVE", gameType: 2)
    let record = LiveActivityManager.FinishedGame(
        gameID: "102", homeScore: 5, awayScore: 3, homeXG: 4.2, awayXG: 2.1, finishedAt: Date())
    GameRowView(game: game, activityManager: previewManager(finished: ["102": record]), prefs: UserPreferences.shared)
        .padding()
        .background(Color(.systemGroupedBackground))
}

// Accepted risk, tracked in TODOS.md ("Home list can show a misleading 50/50
// '(xG: 0.00)' on a zeroed MoneyPuck push"): a zeroed MoneyPuck push still
// renders "(xG: 0.00)" rather than suppressing it. Kept as a preview so the
// visual tradeoff stays visible, not just a line in a TODO.
#Preview("Finished game — zeroed xG (known MoneyPuck bug, see TODOS.md)") {
    let game = NHLGame(id: 103, startTimeUTC: "2026-08-06T23:00:00Z",
                        homeTeam: .init(abbrev: "EDM", score: 3), awayTeam: .init(abbrev: "VAN", score: 2),
                        gameState: "OFF", gameType: 2)
    let record = LiveActivityManager.FinishedGame(
        gameID: "103", homeScore: 3, awayScore: 2, homeXG: 0, awayXG: 0, finishedAt: Date())
    GameRowView(game: game, activityManager: previewManager(finished: ["103": record]), prefs: UserPreferences.shared)
        .padding()
        .background(Color(.systemGroupedBackground))
}

// Regression check: in-progress and upcoming rows must show no xG / persisted
// data at all, even sitting next to a finished row in the same list.
#Preview("Mixed list — finished row next to live/upcoming") {
    let live = NHLGame(id: 104, startTimeUTC: "2026-08-06T22:00:00Z",
                        homeTeam: .init(abbrev: "PIT", score: 2), awayTeam: .init(abbrev: "WSH", score: 1),
                        gameState: "LIVE", gameType: 2)
    let upcoming = NHLGame(id: 105, startTimeUTC: "2026-08-07T02:00:00Z",
                            homeTeam: .init(abbrev: "COL"), awayTeam: .init(abbrev: "DAL"),
                            gameState: "FUT", gameType: 2)
    let finished = NHLGame(id: 106, startTimeUTC: "2026-08-06T20:00:00Z",
                            homeTeam: .init(abbrev: "CGY", score: 6), awayTeam: .init(abbrev: "SEA", score: 1),
                            gameState: "OFF", gameType: 2)
    let record = LiveActivityManager.FinishedGame(
        gameID: "106", homeScore: 6, awayScore: 1, homeXG: 4.8, awayXG: 1.3, finishedAt: Date())
    let manager = previewManager(finished: ["106": record])

    return VStack(spacing: 12) {
        GameRowView(game: live, activityManager: manager, prefs: UserPreferences.shared)
        GameRowView(game: upcoming, activityManager: manager, prefs: UserPreferences.shared)
        GameRowView(game: finished, activityManager: manager, prefs: UserPreferences.shared)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
