import ActivityKit
import SwiftUI
import WidgetKit

// FirepowerWidget — Live Activity views for all 5 render surfaces.
//
// Surfaces:
//   1. Compact stack (lock screen, ~44pt tall)
//   2. Expanded lock screen (~160pt)
//   3. Dynamic Island compact (score-only pill)
//   4. Dynamic Island leading/trailing (split logo + score)
//   5. Dynamic Island expanded (full hierarchy)
//   6. Dynamic Island minimal (icon when multiple LAs exist)
//
// Information hierarchy (lock-screen compact):
//   LEADING: home tricode + score
//   TRAILING: away score + away tricode · period · time
//   xG lives in expanded view only (too dense for compact)

struct FirepowerWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FirepowerActivityAttributes.self) { context in
            // Lock screen / banner
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (user long-presses Dynamic Island)
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        teamLogo(context.attributes.homeTeam, size: 24)
                        Text("\(context.state.homeScore)")
                            .font(.title2.weight(.bold).monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 6) {
                        Text("\(context.state.awayScore)")
                            .font(.title2.weight(.bold).monospacedDigit())
                        teamLogo(context.attributes.awayTeam, size: 24)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.gameState)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    xgRow(home: context.state.homeXG,
                          away: context.state.awayXG,
                          homeTricode: context.attributes.homeTeam,
                          awayTricode: context.attributes.awayTeam)
                        .font(.caption2)
                    if let event = context.state.lastEvent, !event.isEmpty {
                        Text(event)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                // Compact: home team + score
                HStack(spacing: 3) {
                    teamLogo(context.attributes.homeTeam, size: 14)
                    Text("\(context.state.homeScore)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
            } compactTrailing: {
                // Compact: away score + team
                HStack(spacing: 3) {
                    Text("\(context.state.awayScore)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                    teamLogo(context.attributes.awayTeam, size: 14)
                }
            } minimal: {
                // Minimal: just the tracked team's logo
                teamLogo(context.attributes.homeTeam, size: 16)
            }
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let attributes: FirepowerActivityAttributes
    let state: FirepowerActivityAttributes.ContentState

    var body: some View {
        if state.isEnded {
            finalView
        } else {
            inProgressView
        }
    }

    private var inProgressView: some View {
        VStack(spacing: 8) {
            // Score row
            HStack {
                HStack(spacing: 8) {
                    teamLogo(attributes.homeTeam, size: 32)
                    Text("\(state.homeScore)")
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                }
                Spacer()
                Text("·")
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    Text("\(state.awayScore)")
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                    teamLogo(attributes.awayTeam, size: 32)
                }
            }
            .padding(.horizontal, 16)

            // Period + time
            Text(state.gameState)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            // xG row — the differentiator
            xgRow(home: state.homeXG, away: state.awayXG,
                  homeTricode: attributes.homeTeam, awayTricode: attributes.awayTeam)
                .padding(.top, 2)

            // Last event (EXP-2)
            if let event = state.lastEvent, !event.isEmpty {
                Text(event)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 12)
    }

    private var finalView: some View {
        VStack(spacing: 6) {
            Text("Final")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())

            HStack {
                HStack(spacing: 8) {
                    teamLogo(attributes.homeTeam, size: 28)
                    Text("\(state.homeScore)")
                        .font(.title.weight(.bold).monospacedDigit())
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("\(state.awayScore)")
                        .font(.title.weight(.bold).monospacedDigit())
                    teamLogo(attributes.awayTeam, size: 28)
                }
            }
            .padding(.horizontal, 16)

            xgRow(home: state.homeXG, away: state.awayXG,
                  homeTricode: attributes.homeTeam, awayTricode: attributes.awayTeam)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Shared helpers

private func xgRow(home: Double, away: Double, homeTricode: String, awayTricode: String) -> some View {
    HStack {
        Text("\(homeTricode) \(String(format: "%.1f", home)) xG")
        Spacer()
        Text("\(String(format: "%.1f", away)) xG \(awayTricode)")
    }
    .padding(.horizontal, 16)
}

@ViewBuilder
private func teamLogo(_ tricode: String, size: CGFloat) -> some View {
    // Logos are bundled PNG assets in Assets.xcassets, named by lowercase tricode.
    // e.g. "bos.png", "nyr.png"
    let name = tricode.lowercased()
    if let _ = UIImage(named: name) {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    } else {
        // Fallback: tricode text if logo asset is missing
        Text(tricode)
            .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
    }
}

// MARK: - Previews (build these on Day 1 in Xcode to verify layout)

#Preview("Lock Screen — In Progress", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020001"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

#Preview("Lock Screen — Final", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020001"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewEnded
}

#Preview("Dynamic Island — In Progress", as: .dynamicIsland(.expanded), using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020001"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}
