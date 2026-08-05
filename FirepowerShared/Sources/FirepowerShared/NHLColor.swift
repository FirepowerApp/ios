import SwiftUI
import UIKit

// NHLColor — team-color utilities shared between the app and widget extension.
//
// Design system rules (from DESIGN.md):
//   1. Primary first: badge fill and xG bar always start with primaryColor.
//   2. Visibility outline: when a fill's luminance < darkPrimaryLuminanceThreshold,
//      the caller adds a stroke outline so the shape reads on the near-black widget
//      background. The primary color is kept — dark-navy teams (EDM, FLA, NSH, WSH,
//      WPG, SEA) keep their navy fill. Check with needsVisibilityOutline(_:).
//   3. Collision rule: if home and away primaries are perceptually similar (normalized
//      sRGB distance < 0.15), a three-level resolution applies — away secondary, then
//      bidirectional home-secondary flip, then white/black both-fail fallback. See
//      badgeColors() doc for details.
//   4. Foreground on fill: prefers the team's secondaryColor when it clears 3:1 contrast;
//      falls back to white or black.
//
// All functions are pure — no state, no side effects.

// MARK: - Color(hex:)

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: Double
        switch cleaned.count {
        case 6: // RRGGBB
            (r, g, b, a) = (Double((value >> 16) & 0xFF) / 255,
                            Double((value >> 8)  & 0xFF) / 255,
                            Double( value        & 0xFF) / 255,
                            1)
        case 8: // RRGGBBAA
            (r, g, b, a) = (Double((value >> 24) & 0xFF) / 255,
                            Double((value >> 16) & 0xFF) / 255,
                            Double((value >> 8)  & 0xFF) / 255,
                            Double( value        & 0xFF) / 255)
        default:
            (r, g, b, a) = (0, 0, 0, 1)
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Luminance

public extension Color {
    // WCAG 2.1 relative luminance — 0 (black) to 1 (white).
    var relativeLuminance: Double {
        guard let ui = UIColor(self).cgColor.components, ui.count >= 3 else { return 0 }
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(ui[0]) + 0.7152 * lin(ui[1]) + 0.0722 * lin(ui[2])
    }
}

// MARK: - Badge color resolution

public enum NHLColor {

    // Normalized Euclidean distance in sRGB (0–1).
    // Values < 0.15 cover known collision pairs (BOS gold vs PIT gold, NYR vs NYI blue).
    static let collisionThreshold: Double = 0.15

    // Luminance floor for the near-black widget background (~85% black). Colors below
    // this threshold are invisible without an outline. 0.015 catches near-black teams
    // (LAK #111111, SEA #001628, EDM/FLA/NSH/WSH/WPG #041E42) while preserving
    // visually distinct dark colors like NYR royal blue (#0038A8, lum ~0.058).
    public static let darkPrimaryLuminanceThreshold: Double = 0.015

    /// Whether a fill color needs a stroke outline to stay readable on the dark widget
    /// background. Used by TeamBadge and XGSection to conditionally add overlays.
    public static func needsVisibilityOutline(_ color: Color) -> Bool {
        color.relativeLuminance < darkPrimaryLuminanceThreshold
    }

    /// Resolve badge fill colors for home and away teams.
    ///
    /// Three-level collision resolution:
    ///   1. No collision → both primaries.
    ///   2. Away secondary viable (lum ≥ threshold) → away uses secondary.
    ///      E.g. NYR/NYI blue: NYI swaps to orange.
    ///   3. Away secondary dark → home uses its secondary instead (bidirectional flip).
    ///      E.g. DET/CHI red: DET flips to white (#FFFFFF).
    ///      Sub-case — both secondaries dark ("both-fail", e.g. BOS/PIT gold,
    ///      CHI/NJD red): try white first. If home primary clears the text contrast
    ///      floor on white, home fills white and `homePrimaryText` is set so callers
    ///      render the primary as tricode text (e.g. red "NJD" on white). If home
    ///      primary fails on white (e.g. BOS/PIT gold at 1.7:1), home fills its black
    ///      secondary; callers detect the outlined-black case via
    ///      `needsVisibilityOutline(homeFill) && !needsVisibilityOutline(homePrimary)`.
    ///
    /// - Returns: `(homeFill, awayFill, homePrimaryText)`. `homePrimaryText` is true
    ///   when home fill is white from the both-fail fallback — callers should use
    ///   homePrimary as the tricode text color instead of the secondary.
    ///   Call `needsVisibilityOutline(_:)` per fill and add a stroke overlay when true.
    public static func badgeColors(
        homePrimary: String, homeSecondary: String,
        awayPrimary: String, awaySecondary: String
    ) -> (home: Color, away: Color, homePrimaryText: Bool) {
        let homeResolved = Color(hex: homePrimary)
        let awayResolved = Color(hex: awayPrimary)

        guard rgbDistance(homeResolved, awayResolved) < collisionThreshold else {
            return (homeResolved, awayResolved, false)
        }

        // Level 2: try away secondary.
        let awaySecondaryColor = Color(hex: awaySecondary)
        if awaySecondaryColor.relativeLuminance >= darkPrimaryLuminanceThreshold {
            return (homeResolved, awaySecondaryColor, false)
        }

        // Level 3: away secondary too dark — flip home to its secondary instead.
        let homeSecondaryColor = Color(hex: homeSecondary)

        // Both-fail: home secondary also too dark. Try white — if home primary clears
        // the text contrast floor on white, white is the cleanest option: visible without
        // an outline, and the primary color reads as tricode text (red "NJD" at 5.6:1).
        // Gold teams (BOS/PIT ~1.7:1) fail here and fall through to the black secondary.
        if homeSecondaryColor.relativeLuminance < darkPrimaryLuminanceThreshold {
            if contrastRatio(homeResolved, .white) >= badgeTextContrastFloor {
                return (.white, awayResolved, true)
            }
        }

        return (homeSecondaryColor, awayResolved, false)
    }

    // WCAG AA contrast floor for large/bold text. The tricode is 12pt heavy, which
    // qualifies as large text, so 3:1 is the legibility bar a team's secondary color
    // must clear before it's used as the badge text in place of plain white/black.
    static let badgeTextContrastFloor: Double = 3.0

    /// Pick the foreground text color for the tricode drawn on `fill`.
    ///
    /// Priority: secondary → primary (optional) → white or black.
    /// The secondary is tried first so both team colors appear on the badge (e.g. VGK
    /// steel fill + gold tricode). If it fails the contrast floor, `primary` is tried
    /// next — this surfaces the team's actual brand color in collision cases where the
    /// badge fill is the secondary (e.g. DET white badge → red tricode at 5.6:1).
    /// Plain white or black is the last resort.
    public static func badgeTextColor(fill: Color, secondary: Color, primary: Color? = nil) -> Color {
        if contrastRatio(secondary, fill) >= badgeTextContrastFloor {
            return secondary
        }
        if let primary, contrastRatio(primary, fill) >= badgeTextContrastFloor {
            return primary
        }
        return contrastRatio(.white, fill) >= contrastRatio(.black, fill) ? .white : .black
    }

    // WCAG relative-luminance contrast ratio (1–21).
    static func contrastRatio(_ a: Color, _ b: Color) -> Double {
        let la = a.relativeLuminance, lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    // MARK: - Internal helpers

    static func rgbDistance(_ a: Color, _ b: Color) -> Double {
        guard
            let ua = UIColor(a).cgColor.components, ua.count >= 3,
            let ub = UIColor(b).cgColor.components, ub.count >= 3
        else { return 1 }
        let dr = ua[0] - ub[0], dg = ua[1] - ub[1], db = ua[2] - ub[2]
        return sqrt(dr*dr + dg*dg + db*db) / sqrt(3)
    }
}
