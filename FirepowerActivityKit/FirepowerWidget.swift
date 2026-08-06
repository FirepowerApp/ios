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
//   - Loser score dimmed on Final; winner badge stays as tricode.
//   - DI minimal shows pinnedTricode (fallback home).
//   - Dynamic Type capped: .xLarge lock screen, .large DI (fixed heights).
//   - VoiceOver: combined label on container.

enum IslandRegion {
    case leading
    case trailing
}

struct FirepowerWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FirepowerActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activitySystemActionForegroundColor(.white)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    let winner = context.state.winnerTricode(
                        homeTeam: context.attributes.homeTeam, awayTeam: context.attributes.awayTeam)
                    @ScaledMetric(relativeTo: .title)
                    var imageSize: CGFloat = 32
                    teamSide(
                        tricode: context.attributes.homeTeam,
                        score: context.state.homeScore,
                        logoSize: imageSize,
                        isLoser: winner == context.attributes.awayTeam,
                        position: IslandRegion.leading
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    let winner = context.state.winnerTricode(
                        homeTeam: context.attributes.homeTeam, awayTeam: context.attributes.awayTeam)
                    @ScaledMetric(relativeTo: .title)
                    var imageSize: CGFloat = 32
                    teamSide(
                        tricode: context.attributes.awayTeam,
                        score: context.state.awayScore,
                        logoSize: imageSize,
                        isLoser: winner == context.attributes.homeTeam,
                        position: IslandRegion.trailing
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.clockLabel(startTime: context.attributes.startTime, isStale: context.isStale))
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
                HStack(spacing: 2) {
                    teamLogo(context.attributes.homeTeam, size: 22)
                    Text("\(context.state.homeScore)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
            } compactTrailing: {
                HStack(spacing: 2) {
                    Text("\(context.state.awayScore)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                    teamLogo(context.attributes.awayTeam, size: 22)
                }
            } minimal: {
                let shown = context.attributes.pinnedTricode ?? context.attributes.homeTeam
                teamLogo(shown, size: 28)
            }
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let attributes: FirepowerActivityAttributes
    let state: FirepowerActivityAttributes.ContentState
    let isStale: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if state.isEnded {
                finalView
            } else {
                inProgressView
            }
        }
        // In light mode the system material shows through the semi-transparent tint, producing
        // a white background on device. Explicit black fills the view so the preview canvas
        // renders it correctly too (activityBackgroundTint is ignored by the canvas).
        .background(colorScheme == .light ? Color.black : Color.clear)
        .activityBackgroundTint(colorScheme == .light ? .black : Color.black.opacity(0.85))
        // Force children to always render in dark mode so adaptive colors (.primary, .secondary)
        // stay white on the black background in both light and dark system appearance.
        .environment(\.colorScheme, .dark)
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
        let clock = state.clockLabel(startTime: attributes.startTime, isStale: isStale)

        return HStack(alignment: .center, spacing: 0) {
            // Home side
            HStack(spacing: 8) {
                TeamBadge(tricode: attributes.homeTeam,
                          homeTricode: attributes.homeTeam, awayTricode: attributes.awayTeam)
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
                          homeTricode: attributes.homeTeam, awayTricode: attributes.awayTeam)
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

    var body: some View {
        let home = NHLTeamColors.colors(for: homeTricode)
        let away = NHLTeamColors.colors(for: awayTricode)

        // badgeColors() applies three-level collision resolution. Always pass real
        // home/away order so the result is correct regardless of which badge renders.
        let (homeFill, awayFill, homePrimaryText) = NHLColor.badgeColors(
            homePrimary: home?.primaryColor ?? "#888888",
            homeSecondary: home?.secondaryColor ?? "#FFFFFF",
            awayPrimary: away?.primaryColor ?? "#888888",
            awaySecondary: away?.secondaryColor ?? "#FFFFFF"
        )
        let isHome = (tricode == homeTricode)
        let fill = isHome ? homeFill : awayFill
        let selfPrimary = (isHome ? home : away)?.primaryColor ?? "#FFFFFF"
        let selfSec = (isHome ? home : away)?.secondaryColor ?? "#FFFFFF"

        // homePrimaryText: both-fail white fallback — home fills white, primary is the
        // text color (e.g. red "NJD" on white at 5.6:1). Secondary (black) would also
        // pass contrast on white but loses team color.
        //
        // isInvertedHome: both-fail black fallback — home fills its dark secondary,
        // primary is the text color (e.g. gold "BOS" on black at 12:1).
        // TODO: derived from fill rather than an explicit badgeColors signal — correct
        // for all current NHL teams, but if a team's primaryColor is changed to something
        // bright while keeping a dark secondary, this could misfire on non-collision games.
        // Consider extending badgeColors' return tuple with a homeUsesBlackFill flag.
        let isInvertedHome = isHome
            && NHLColor.needsVisibilityOutline(fill)
            && !NHLColor.needsVisibilityOutline(Color(hex: selfPrimary))
        let textColor: Color = {
            if isHome && homePrimaryText { return Color(hex: selfPrimary) }
            if isInvertedHome { return Color(hex: selfPrimary) }
            return NHLColor.badgeTextColor(fill: fill, secondary: Color(hex: selfSec),
                                           primary: Color(hex: selfPrimary))
        }()
        let addOutline = NHLColor.needsVisibilityOutline(fill)

        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .frame(width: 44, height: 26)
            if addOutline {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 44, height: 26)
            }
            Text(tricode)
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
        let (homeColor, awayColor, _) = NHLColor.badgeColors(
            homePrimary: h?.primaryColor ?? "#888888",
            homeSecondary: h?.secondaryColor ?? "#FFFFFF",
            awayPrimary: a?.primaryColor ?? "#888888",
            awaySecondary: a?.secondaryColor ?? "#FFFFFF"
        )

        // Bar color always matches badge fill — homeColor and awayColor are already the
        // resolved badge fills from badgeColors. needsVisibilityOutline handles the outline
        // for both capsules, including the black home bar in the both-fail inversion case.
        let homeNeedsOutline = NHLColor.needsVisibilityOutline(homeColor)
        let awayNeedsOutline = NHLColor.needsVisibilityOutline(awayColor)

        // Each bar is proportional to that team's raw xG share: homeXG / total.
        // At 3–1 xG the home bar is 75% wide, away is 25%. At 0–0 (or any tie)
        // both bars are 50%. No saturation is possible since proportions sum to 1.
        let combined = homeXG + awayXG
        let homeFraction = combined < 0.1 ? 0.5 : homeXG / combined
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
            // the other retracts. Dark-primary teams (navy etc.) get a white stroke
            // so the capsule shape reads on the near-black background.
            GeometryReader { geo in
                let w = geo.size.width
                VStack(alignment: .leading, spacing: 3) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(homeColor)
                        if homeNeedsOutline {
                            Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                        }
                    }
                    .frame(width: max(w * homeFraction, 2), height: 7)

                    ZStack(alignment: .leading) {
                        Capsule().fill(awayColor)
                        if awayNeedsOutline {
                            Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                        }
                    }
                    .frame(width: max(w * awayFraction, 2), height: 7)
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
    isLoser: Bool,
    position: IslandRegion
) -> some View {
    HStack(spacing: 1) {
        if (position == IslandRegion.leading) {
            teamLogo(tricode, size: logoSize)
            Text("\(score)")
                .font(.title.weight(.bold).monospacedDigit())
                .opacity(isLoser ? 0.55 : 1)
        }
        else if position == IslandRegion.trailing {
            Text("\(score)")
                .font(.title.weight(.bold).monospacedDigit())
                .opacity(isLoser ? 0.55 : 1)
            teamLogo(tricode, size: logoSize)
        }
            
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

// Tracked after puck drop (or once the start time passes): plain "Pregame"
// until the first channel push arrives.
#Preview("Lock — Pregame", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020001"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewEmpty
}

// Tracked hours before puck drop: the center shows the scheduled local start
// time (via attributes.startTime) instead of "Pregame".
#Preview("Lock — Pregame (scheduled time)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020001",
    startTime: Date().addingTimeInterval(8 * 3600)
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewEmpty
}


#Preview("Lock — Dark primary (LAK home, SEA away)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "LAK", awayTeam: "SEA", gameID: "2025020003"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

// EDM navy badge + bar: both show navy fill with white outline (not orange swap).
#Preview("Lock — EDM navy home", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "EDM", awayTeam: "VGK", gameID: "2025020020"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

// DET home vs CHI away: both red primaries collide. CHI secondary (#000000) too dark
// (L2 fails) → bidirectional flip: DET uses its white secondary. CHI stays red.
// DET: white badge + red text (5.6:1) + white bar. CHI: red badge + black text + red bar.
#Preview("Lock — DET home vs CHI (bidirectional flip)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "DET", awayTeam: "CHI", gameID: "2025020021"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

// CHI home vs DET away: same collision, opposite sides. DET secondary (#FFFFFF) is
// viable (L2) → DET flips to white. CHI home stays red.
// CHI: red badge + black text + red bar. DET: white badge + red text (5.6:1) + white bar.
#Preview("Lock — CHI home vs DET (bidirectional flip)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "CHI", awayTeam: "DET", gameID: "2025020025"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

// BOS home vs PIT away: both-fail (both secondaries #000000).
// BOS: black badge + white outline + gold text + black bar (outlined).
// PIT: gold badge + black text + gold bar.
#Preview("Lock — BOS home vs PIT (both-fail)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "PIT", gameID: "2025020023"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

// PIT home vs BOS away: same both-fail, opposite sides.
// PIT: black badge + white outline + gold text + black bar (outlined).
// BOS: gold badge + black text + gold bar.
#Preview("Lock — PIT home vs BOS (both-fail)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "PIT", awayTeam: "BOS", gameID: "2025020026"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

// CHI home vs NJD away: both-fail, red primary passes on white (5.6:1).
// CHI: white badge + red text + white bar. NJD: red badge + black text + red bar.
#Preview("Lock — CHI home vs NJD (both-fail)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "CHI", awayTeam: "NJD", gameID: "2025020024"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

// NJD home vs CHI away: same both-fail, opposite sides.
// NJD: white badge + red text + white bar. CHI: red badge + black text + red bar.
#Preview("Lock — NJD home vs CHI (both-fail)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "NJD", awayTeam: "CHI", gameID: "2025020027"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

// WSH home vs CAR: WSH primary is navy (#041E42), which is below the visibility
// threshold and gets a white outline — but stays navy, NOT swapped to its red
// secondary (#C8102E). Verifies the old darkPrimaryGuard swap is gone.
// WSH: navy badge + white outline + white text + navy bar (outlined).
// CAR: red badge + white text + red bar.
#Preview("Lock — WSH navy home vs CAR (no red swap)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "WSH", awayTeam: "CAR", gameID: "2025020028"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

// Final state: loser score dims; both badges still show their tricode (no WIN pill).
#Preview("Lock — Final, no WIN badge (EDM wins)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "EDM", awayTeam: "VGK", gameID: "2025020022"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewEnded
}

#Preview("DI — Expanded", as: .dynamicIsland(.expanded), using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020001",
    pinnedTricode: "NYR"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.preview
}

// MARK: New-design showcase previews

// Both teams at exactly 1.00 xG — bars are identical length.
#Preview("Lock — xG tied 1.00/1.00", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020014"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewXGTied
}

// Stacked bars at an even xG: both bars are half-width (home from the left,
// away from the right), so the gap reads as zero.
#Preview("Lock — xG even (50/50 bars)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "BOS", awayTeam: "NYR", gameID: "2025020010"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewXGEven
}

// The DESIGN.md example: a 1.42–1.02 edge → ~70/30 split, and the VGK home
// badge shows the secondary-color tricode (gold on steel).
#Preview("Lock — xG lead (70/30) + VGK badge", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "VGK", awayTeam: "DET", gameID: "2025020011"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewXGLead
}

// Gap > 1.0 saturates the leader's bar; the trailing team keeps its 2% sliver.
#Preview("Lock — xG blowout (bar saturates)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "NSH", awayTeam: "DAL", gameID: "2025020012"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewXGBlowout
}

// Both badges carry the team's secondary color as the tricode text: VGK gold on
// steel, BUF gold on navy.
#Preview("Lock — secondary badges (VGK + BUF gold)", as: .content, using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "VGK", awayTeam: "BUF", gameID: "2025020013"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewXGLead
}

// Dynamic Island expanded with the 2-decimal xG row.
#Preview("DI — Expanded (2-decimal xG)", as: .dynamicIsland(.expanded), using: FirepowerActivityAttributes(
    sport: "nhl", homeTeam: "VGK", awayTeam: "DET", gameID: "2025020011",
    pinnedTricode: "VGK"
)) {
    FirepowerWidget()
} contentStates: {
    FirepowerActivityAttributes.ContentState.previewXGLead
}
