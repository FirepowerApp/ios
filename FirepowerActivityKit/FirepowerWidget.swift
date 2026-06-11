import ActivityKit
import FirepowerShared
import SwiftUI
import WidgetKit

// FirepowerWidget — Live Activity views for all 5 render surfaces.
//
// Surfaces:
//   1. Lock screen expanded — in-progress   (~160pt tall)
//   2. Lock screen expanded — Final
//   3. Dynamic Island compact (score pill, ~30pt)
//   4. Dynamic Island expanded (full hierarchy)
//   5. Dynamic Island minimal (single logo when multiple LAs exist)
//
// Design system (DESIGN.md):
//   - Team-colored tricode badges per game; collision + dark-primary guard via NHLColor.
//   - Score: .system(.largeTitle, .rounded, .heavy).monospacedDigit()
//   - Clock/period centered between scores.
//   - Scorer line (eventTeam) aligned left/right toward the scoring team.
//   - WINNER pill + loser dimmed 60% on Final.
//   - DI minimal shows pinnedTricode (fallback home).
//   - Dynamic Type capped: .xLarge lock screen, .large DI (fixed heights).
//   - VoiceOver: combined label on container.

struct FirepowerWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FirepowerActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    let winner = context.state.winnerTricode(
                        homeTeam: context.attributes.homeTeam, awayTeam: context.attributes.awayTeam)
                    teamSide(
                        tricode: context.attributes.homeTeam,
                        score: context.state.homeScore,
                        logoSize: 24,
                        isLoser: winner == context.attributes.awayTeam
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    let winner = context.state.winnerTricode(
                        homeTeam: context.attributes.homeTeam, awayTeam: context.attributes.awayTeam)
                    teamSide(
                        tricode: context.attributes.awayTeam,
                        score: context.state.awayScore,
                        logoSize: 24,
                        isLoser: winner == context.attributes.homeTeam
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.isPregame ? "Pregame" : context.state.isEnded ? "Final" : context.state.gameState)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        xgRow(home: context.state.homeXG, away: context.state.awayXG)
                            .font(.caption2)
                        eventLine(state: context.state, homeTeam: context.attributes.homeTeam)
                            .font(.caption2)
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    teamLogo(context.attributes.homeTeam, size: 14)
                    Text("\(context.state.homeScore)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
            } compactTrailing: {
                HStack(spacing: 3) {
                    Text("\(context.state.awayScore)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                    teamLogo(context.attributes.awayTeam, size: 14)
                }
            } minimal: {
                let shown = context.attributes.pinnedTricode ?? context.attributes.homeTeam
                teamLogo(shown, size: 16)
            }
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let attributes: FirepowerActivityAttributes
    let state: FirepowerActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isEnded {
                finalView
            } else {
                inProgressView
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: In-progress

    private var inProgressView: some View {
        VStack(spacing: 8) {
            scoreRow
            XGSection(homeXG: state.homeXG, awayXG: state.awayXG,
                      homeTricode: attributes.homeTeam, awayTricode: attributes.awayTeam)
                .padding(.top, 2)
            eventLine(state: state, homeTeam: attributes.homeTeam)
        }
        .padding(.vertical, 12)
    }

    // MARK: Final

    private var finalView: some View {
        VStack(spacing: 8) {
            scoreRow
            XGSection(homeXG: state.homeXG, awayXG: state.awayXG,
                      homeTricode: attributes.homeTeam, awayTricode: attributes.awayTeam)
                .padding(.top, 2)
        }
        .padding(.vertical, 12)
    }

    // MARK: Score row

    private var scoreRow: some View {
        let winner = state.winnerTricode(homeTeam: attributes.homeTeam, awayTeam: attributes.awayTeam)
        let homeIsWinner = winner == attributes.homeTeam
        let awayIsWinner = winner == attributes.awayTeam
        let clock = state.isPregame ? "Pregame" : state.isEnded ? "" : state.gameState

        return HStack(alignment: .center, spacing: 0) {
            // Home side
            HStack(spacing: 8) {
                TeamBadge(tricode: attributes.homeTeam,
                          homeTricode: attributes.homeTeam, awayTricode: attributes.awayTeam,
                          isWinner: homeIsWinner, showWinnerPill: state.isEnded)
                Text("\(state.homeScore)")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy).monospacedDigit())
                    .opacity(state.isEnded && awayIsWinner ? 0.55 : 1)
            }

            Spacer(minLength: 4)

            // Center: clock or "Final"
            if !clock.isEmpty {
                Text(clock)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 4)

            // Away side
            HStack(spacing: 8) {
                Text("\(state.awayScore)")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy).monospacedDigit())
                    .opacity(state.isEnded && homeIsWinner ? 0.55 : 1)
                TeamBadge(tricode: attributes.awayTeam,
                          homeTricode: attributes.homeTeam, awayTricode: attributes.awayTeam,
                          isWinner: awayIsWinner, showWinnerPill: state.isEnded)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Accessibility

    private var accessibilityDescription: String {
        let home = attributes.homeTeam
        let away = attributes.awayTeam
        var parts = ["\(home) \(state.homeScore), \(away) \(state.awayScore)"]
        if !state.gameState.isEmpty { parts.append(state.gameState) }
        parts.append("expected goals \(String(format: "%.1f", state.homeXG)) to \(String(format: "%.1f", state.awayXG))")
        if let type_ = state.resolvedEventType {
            let detail = state.resolvedEventDetail.flatMap { $0.isEmpty ? nil : $0 }
            let team   = state.resolvedEventTeam ?? ""
            switch type_ {
            case "goal":
                parts.append(detail != nil ? "Goal, \(detail!), \(team)" : "Goal, \(team)")
            case "penalty":
                parts.append(detail != nil ? "Penalty, \(detail!)" : "Penalty")
            default:
                break
            }
        }
        return parts.joined(separator: ". ") + "."
    }
}

// MARK: - TeamBadge

private struct TeamBadge: View {
    let tricode: String        // the team THIS badge represents
    let homeTricode: String    // real home team for the game
    let awayTricode: String    // real away team for the game
    let isWinner: Bool
    let showWinnerPill: Bool

    var body: some View {
        let home = NHLTeamColors.colors(for: homeTricode)
        let away = NHLTeamColors.colors(for: awayTricode)

        // badgeColors() returns (home, away) with the dark-primary guard and the
        // collision rule already applied to the away side. We just pick our side —
        // always pass the real home/away order so the result is correct for both badges.
        let (homeFill, awayFill) = NHLColor.badgeColors(
            homePrimary: home?.primaryColor ?? "#888888", homeSecondary: home?.secondaryColor ?? "#FFFFFF",
            awayPrimary: away?.primaryColor ?? "#888888", awaySecondary: away?.secondaryColor ?? "#FFFFFF"
        )
        let isHome = (tricode == homeTricode)
        let fill = isHome ? homeFill : awayFill
        let selfSec = (isHome ? home : away)?.secondaryColor ?? "#FFFFFF"
        let textColor = NHLColor.badgeTextColor(fill: fill, secondary: Color(hex: selfSec))

        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .frame(width: 44, height: 26)

            Text(showWinnerPill && isWinner ? "WIN" : tricode)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(textColor)
        }
    }
}

// MARK: - xG Section (the app's signature metric)

private struct XGSection: View {
    let homeXG: Double
    let awayXG: Double
    let homeTricode: String
    let awayTricode: String

    var body: some View {
        let h = NHLTeamColors.colors(for: homeTricode)
        let a = NHLTeamColors.colors(for: awayTricode)
        let (homeColor, awayColor) = NHLColor.badgeColors(
            homePrimary: h?.primaryColor ?? "#888888", homeSecondary: h?.secondaryColor ?? "#FFFFFF",
            awayPrimary: a?.primaryColor ?? "#888888", awaySecondary: a?.secondaryColor ?? "#FFFFFF"
        )
        // Bars encode the xG *gap*, not each team's raw share: at an even xG both
        // teams own half the width, and every 1.0 of separation shifts the split by
        // half the width toward the leader (so a 1.40–1.00 edge reads as 70 / 30).
        // Clamped so the trailing team always keeps a visible sliver. A 0-0 game
        // lands at 50/50 naturally, so it never implies one team is dominating.
        let homeFraction = min(max(0.5 + (homeXG - awayXG) / 2, 0.02), 0.98)
        let awayFraction = 1 - homeFraction

        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.2f", homeXG))
                    .font(.system(.title3, design: .rounded, weight: .heavy).monospacedDigit())
                Spacer()
                Text("xG")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", awayXG))
                    .font(.system(.title3, design: .rounded, weight: .heavy).monospacedDigit())
            }

            // Two stacked team-colored bars — home grows from the left, away from
            // the right — so the gap between their tips reads as the size of the
            // xG lead, and a swing toward one team visibly lengthens its bar while
            // the other retracts.
            GeometryReader { geo in
                let w = geo.size.width
                VStack(spacing: 3) {
                    HStack(spacing: 0) {
                        Capsule().fill(homeColor)
                            .frame(width: max(w * homeFraction, 2))
                        Spacer(minLength: 0)
                    }
                    .frame(height: 7)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Capsule().fill(awayColor)
                            .frame(width: max(w * awayFraction, 2))
                    }
                    .frame(height: 7)
                }
            }
            .frame(height: 17)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Shared helpers

@ViewBuilder
private func teamSide(
    tricode: String,
    score: Int,
    logoSize: CGFloat,
    isLoser: Bool
) -> some View {
    HStack(spacing: 4) {
        teamLogo(tricode, size: logoSize)
        Text("\(score)")
            .font(.title.weight(.bold).monospacedDigit())
            .opacity(isLoser ? 0.55 : 1)
    }
}

@ViewBuilder
private func xgRow(home: Double, away: Double) -> some View {
    HStack {
        Text("xG: \(String(format: "%.2f", home))")
        Spacer()
        Text("xG: \(String(format: "%.2f", away))")
    }
    .padding(.horizontal, 16)
    .font(.caption.monospacedDigit())
    .foregroundStyle(.secondary)
}

@ViewBuilder
private func eventLine(
    state: FirepowerActivityAttributes.ContentState,
    homeTeam: String
) -> some View {
    if let type_ = state.resolvedEventType, type_ == "goal" || type_ == "penalty" {
        let detail = state.resolvedEventDetail.flatMap { $0.isEmpty ? nil : $0 }
        let label: String = {
            switch type_ {
            case "goal":    return detail.map { "Goal, \($0)" } ?? "Goal"
            case "penalty": return detail.map { "Penalty, \($0)" } ?? "Penalty"
            default:        return ""
            }
        }()

        Text(label)
            .font(.caption.italic())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
    }
}

@ViewBuilder
private func teamLogo(_ tricode: String, size: CGFloat) -> some View {
    let name = tricode.lowercased()
    if let _ = UIImage(named: name) {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    } else {
        Text(tricode)
            .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
    }
}

// MARK: - Previews

#Preview("Lock — In Progress", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020001",
    pinnedTricode: "NYR"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

#Preview("Lock — Final (BOS wins)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020001"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewEnded
}

#Preview("Lock — Pregame", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020001"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewEmpty
}

#Preview("Lock — Collision (BOS vs PIT)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "PIT", gameID: "2025020002"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

#Preview("Lock — Dark primary (LAK)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "LAK", awayTeam: "SEA", gameID: "2025020003"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

#Preview("DI — Expanded", as: .dynamicIsland(.expanded), using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020001",
    pinnedTricode: "NYR"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}
