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
                    teamSide(
                        tricode: context.attributes.homeTeam,
                        score: context.state.homeScore,
                        logoSize: 24,
                        isWinner: context.state.isEnded &&
                            context.state.winnerTricode(
                                homeTeam: context.attributes.homeTeam,
                                awayTeam: context.attributes.awayTeam) == context.attributes.homeTeam,
                        isLoser: context.state.isEnded &&
                            context.state.winnerTricode(
                                homeTeam: context.attributes.homeTeam,
                                awayTeam: context.attributes.awayTeam) == context.attributes.awayTeam,
                        attributes: context.attributes
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    teamSide(
                        tricode: context.attributes.awayTeam,
                        score: context.state.awayScore,
                        logoSize: 24,
                        isWinner: context.state.isEnded &&
                            context.state.winnerTricode(
                                homeTeam: context.attributes.homeTeam,
                                awayTeam: context.attributes.awayTeam) == context.attributes.awayTeam,
                        isLoser: context.state.isEnded &&
                            context.state.winnerTricode(
                                homeTeam: context.attributes.homeTeam,
                                awayTeam: context.attributes.awayTeam) == context.attributes.homeTeam,
                        attributes: context.attributes
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
        VStack(spacing: 6) {
            scoreRow
            xgRow(home: state.homeXG, away: state.awayXG)
                .padding(.top, 2)
            eventLine(state: state, homeTeam: attributes.homeTeam)
        }
        .padding(.vertical, 12)
    }

    // MARK: Final

    private var finalView: some View {
        let winner = state.winnerTricode(homeTeam: attributes.homeTeam, awayTeam: attributes.awayTeam)
        return VStack(spacing: 6) {
            scoreRow
            xgRow(home: state.homeXG, away: state.awayXG)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .environment(\.winnerTricode, winner)
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
                TeamBadge(tricode: attributes.homeTeam, opponent: attributes.awayTeam,
                          isAway: false, isWinner: homeIsWinner, showWinnerPill: state.isEnded)
                teamLogo(attributes.homeTeam, size: 32)
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
                teamLogo(attributes.awayTeam, size: 32)
                TeamBadge(tricode: attributes.awayTeam, opponent: attributes.homeTeam,
                          isAway: true, isWinner: awayIsWinner, showWinnerPill: state.isEnded)
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
    let tricode: String
    let opponent: String
    let isAway: Bool        // true → this badge is the away team (collision uses opponent as home)
    let isWinner: Bool
    let showWinnerPill: Bool

    var body: some View {
        let home = NHLTeamColors.colors(for: tricode)
        let away = NHLTeamColors.colors(for: opponent)

        let homePri = home?.primaryColor   ?? "#888888"
        let homeSec = home?.secondaryColor ?? "#FFFFFF"
        let awayPri = away?.primaryColor   ?? "#888888"
        let awaySec = away?.secondaryColor ?? "#FFFFFF"

        // Resolve fill: apply dark-primary guard and collision rule.
        // badgeColors() treats first arg as home. For the away badge, swap arg order so
        // "self" is always first — then take the home result. This ensures the collision
        // rule sees our color as home and may swap the opponent's color, not ours.
        let resolvedColors = isAway
            ? NHLColor.badgeColors(homePrimary: awayPri, homeSecondary: awaySec,
                                   awayPrimary: homePri, awaySecondary: homeSec)
            : NHLColor.badgeColors(homePrimary: homePri, homeSecondary: homeSec,
                                   awayPrimary: awayPri, awaySecondary: awaySec)
        let fill = resolvedColors.home   // always "home" = self in the arg order above
        let selfSec = isAway ? awaySec : homeSec
        let textColor = NHLColor.badgeTextColor(fill: fill, secondary: Color(hex: selfSec))

        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .frame(width: 34, height: 20)

            if showWinnerPill && isWinner {
                Text("WIN")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(textColor)
            } else {
                Text(tricode)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(textColor)
            }
        }
    }
}

// MARK: - Shared helpers

@ViewBuilder
private func teamSide(
    tricode: String,
    score: Int,
    logoSize: CGFloat,
    isWinner: Bool,
    isLoser: Bool,
    attributes: FirepowerActivityAttributes
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
        Text("\(String(format: "%.1f", home)) xG")
        Spacer()
        Text("xG \(String(format: "%.1f", away))")
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
            case "goal":    return detail.map { "Goal — \($0)" } ?? "Goal"
            case "penalty": return detail.map { "Penalty — \($0)" } ?? "Penalty"
            default:        return ""
            }
        }()
        let alignHome = (state.resolvedEventTeam ?? homeTeam) == homeTeam

        HStack {
            if alignHome {
                Text(label)
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            } else {
                Spacer()
                Text(label)
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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

// MARK: - Environment key for winner tricode

private struct WinnerTricodeKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private extension EnvironmentValues {
    var winnerTricode: String? {
        get { self[WinnerTricodeKey.self] }
        set { self[WinnerTricodeKey.self] = newValue }
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
