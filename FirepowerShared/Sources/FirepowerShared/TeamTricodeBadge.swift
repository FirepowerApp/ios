import SwiftUI

/// A team-colored tricode badge — the fallback rendering wherever a team's logo
/// image isn't available (e.g. a build configuration that excludes the licensed
/// crest assets via EXCLUDED_SOURCE_FILE_NAMES for App Store submission).
///
/// Deliberately mirrors the Live Activity lock screen's TeamBadge color-resolution
/// algorithm (same NHLColor.badgeColors/badgeTextColor/needsVisibilityOutline calls,
/// same three-level collision + dark-primary guard) so the fallback reads as the
/// same design language, just laid out as a square to match a logo image's footprint
/// instead of the lock screen's fixed 44x26 rectangle.
public struct TeamTricodeBadge: View {
    public let tricode: String        // the team THIS badge represents
    public let homeTricode: String    // real home team for the game (for collision resolution)
    public let awayTricode: String    // real away team for the game
    public let size: CGFloat

    public init(tricode: String, homeTricode: String, awayTricode: String, size: CGFloat) {
        self.tricode = tricode
        self.homeTricode = homeTricode
        self.awayTricode = awayTricode
        self.size = size
    }

    public var body: some View {
        let home = NHLTeamColors.colors(for: homeTricode)
        let away = NHLTeamColors.colors(for: awayTricode)

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

        // Same both-fail black-fallback detection as TeamBadge: derived from the fill
        // rather than an explicit signal, correct for all current NHL teams.
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
        let cornerRadius = size * 0.22

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(fill)
            if addOutline {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: max(1, size * 0.045))
            }
            Text(tricode)
                .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                .foregroundStyle(textColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, size * 0.06)
        }
        .frame(width: size, height: size)
    }
}
