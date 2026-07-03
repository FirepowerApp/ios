import ActivityKit
import FirepowerShared
import SwiftUI

struct GameRowView: View {

    let game: NHLGame
    @ObservedObject var activityManager: LiveActivityManager
    @ObservedObject var prefs: UserPreferences

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
            Image(tricode.lowercased())
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color(.tertiarySystemGroupedBackground))
                        .frame(width: 26, height: 26)
                )

            Text(tricode)
                .font(.system(.body, design: .rounded).weight(.semibold))

            if let score = score {
                Text("\(score)")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(game.isLive ? .primary : .secondary)
            }
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
            let canStart = homeTeam?.channelId.isEmpty == false
                        || awayTeam?.channelId.isEmpty == false
            Button {
                guard canStart else { return }
                Task {
                    isStarting = true
                    defer { isStarting = false }
                    await activityManager.startActivity(
                        homeTeam: game.homeTeam.abbrev,
                        awayTeam: game.awayTeam.abbrev,
                        gameID: String(game.id)
                    )
                }
            } label: {
                Text(canStart ? "Track" : "Soon")
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
}
