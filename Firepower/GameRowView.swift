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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Teams column
                VStack(alignment: .leading, spacing: 6) {
                    teamRow(tricode: game.awayTeam.abbrev, score: game.awayTeam.score)
                    Text("@")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                    teamRow(tricode: game.homeTeam.abbrev, score: game.homeTeam.score)
                }

                Spacer()

                // State / action column
                VStack(alignment: .trailing, spacing: 8) {
                    stateLabel
                    if game.isUpcoming || game.isLive {
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

    private func teamRow(tricode: String, score: Int?) -> some View {
        HStack(spacing: 8) {
            teamImage(tricode: tricode)

            // Team name, not tricode — the tricode already appears inside the logo
            // (or its fallback badge), so repeating it here read as "PIT PIT".
            Text(NHLTeam.team(for: tricode)?.shortName ?? tricode)
                .font(.system(.body, design: .rounded).weight(.semibold))

            if let score = score {
                Text("\(score)")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(game.isLive ? .primary : .secondary)
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
        if game.isLive {
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
