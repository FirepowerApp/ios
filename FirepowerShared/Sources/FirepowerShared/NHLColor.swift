import SwiftUI
import UIKit

// NHLColor — team-color utilities shared between the app and widget extension.
//
// Design system rules (from DESIGN.md):
//   1. Primary first: start with primaryColor.
//   2. Dark-primary guard: if primary luminance < 0.08 on the dark widget background,
//      swap to secondaryColor.
//   3. Collision rule: if home and away resolved colors are perceptually similar
//      (normalized RGB distance < 0.15), away swaps to its secondaryColor.
//   4. Foreground on fill: white when fill luminance < 0.5, else secondaryColor.
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

    // A color is "too dark" for the Live Activity's ~85% black background
    // when its luminance is below this value.
    static let darkPrimaryLuminanceThreshold: Double = 0.08

    /// Resolve badge fill colors for home and away teams, applying dark-primary
    /// guard then collision rule.
    ///
    /// - Returns: `(homeFill, awayFill)` hex-initialized Colors ready for badge backgrounds.
    public static func badgeColors(
        homePrimary: String, homeSecondary: String,
        awayPrimary: String, awaySecondary: String
    ) -> (home: Color, away: Color) {
        // Step 1 — dark-primary guard: swap to secondary if primary disappears on dark bg
        let homeResolved = darkPrimaryGuard(primary: homePrimary, secondary: homeSecondary)
        let awayResolved = darkPrimaryGuard(primary: awayPrimary, secondary: awaySecondary)

        // Step 2 — collision: if resolved colors are too similar, away swaps to secondary
        if rgbDistance(homeResolved, awayResolved) < collisionThreshold {
            return (homeResolved, Color(hex: awaySecondary))
        }
        return (homeResolved, awayResolved)
    }

    /// Pick the foreground text color for text drawn on `fill`.
    /// Returns white for dark fills, `secondary` for light fills.
    public static func badgeTextColor(fill: Color, secondary: Color) -> Color {
        fill.relativeLuminance < 0.5 ? .white : secondary
    }

    // MARK: - Internal helpers

    static func darkPrimaryGuard(primary: String, secondary: String) -> Color {
        let c = Color(hex: primary)
        return c.relativeLuminance < darkPrimaryLuminanceThreshold ? Color(hex: secondary) : c
    }

    static func rgbDistance(_ a: Color, _ b: Color) -> Double {
        guard
            let ua = UIColor(a).cgColor.components, ua.count >= 3,
            let ub = UIColor(b).cgColor.components, ub.count >= 3
        else { return 1 }
        let dr = ua[0] - ub[0], dg = ua[1] - ub[1], db = ua[2] - ub[2]
        return sqrt(dr*dr + dg*dg + db*db) / sqrt(3)
    }
}
