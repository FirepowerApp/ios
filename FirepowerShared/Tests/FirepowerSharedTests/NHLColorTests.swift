import Testing
import SwiftUI
@testable import FirepowerShared

// MARK: - Color(hex:)

@Suite("Color(hex:)")
struct ColorHexTests {

    @Test("parses #RRGGBB") func rgbHex() {
        let c = Color(hex: "#FFB81C") // BOS gold
        let ui = UIColor(c)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 1.0)   < 0.01)
        #expect(abs(g - 0.722) < 0.01)
        #expect(abs(b - 0.110) < 0.01)
        #expect(a == 1.0)
    }

    @Test("parses without hash") func noHash() {
        let a = Color(hex: "FFB81C")
        let b = Color(hex: "#FFB81C")
        #expect(UIColor(a) == UIColor(b))
    }

    @Test("malformed hex returns black") func malformed() {
        let c = Color(hex: "ZZZ")
        #expect(UIColor(c) == UIColor(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)))
    }

    @Test("empty string returns black") func empty() {
        let c = Color(hex: "")
        #expect(UIColor(c) == UIColor(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)))
    }
}

// MARK: - Luminance

@Suite("relativeLuminance")
struct LuminanceTests {

    @Test("black = 0") func black() {
        #expect(Color(hex: "#000000").relativeLuminance == 0)
    }

    @Test("white = 1") func white() {
        #expect(abs(Color(hex: "#FFFFFF").relativeLuminance - 1.0) < 0.001)
    }

    @Test("mid-gray between 0 and 1") func midGray() {
        let l = Color(hex: "#808080").relativeLuminance
        #expect(l > 0 && l < 1)
    }

    @Test("BOS gold is light (> 0.5)") func bosGold() {
        #expect(Color(hex: "#FFB81C").relativeLuminance > 0.5)
    }

    @Test("LAK black is very dark (< 0.08)") func lakBlack() {
        #expect(Color(hex: "#111111").relativeLuminance < 0.08)
    }
}

// MARK: - needsVisibilityOutline

@Suite("NHLColor.needsVisibilityOutline")
struct NeedsVisibilityOutlineTests {

    @Test("LAK near-black primary needs outline") func lakNeedsOutline() {
        // LAK #111111 lum ~0.006 < 0.015 threshold
        #expect(NHLColor.needsVisibilityOutline(Color(hex: "#111111")) == true)
    }

    @Test("SEA navy primary needs outline") func seaNeedsOutline() {
        // SEA #001628 lum ~0.007
        #expect(NHLColor.needsVisibilityOutline(Color(hex: "#001628")) == true)
    }

    @Test("EDM navy primary needs outline") func edmNeedsOutline() {
        // EDM/FLA/NSH/WSH/WPG #041E42 lum ~0.014 — just below 0.015
        #expect(NHLColor.needsVisibilityOutline(Color(hex: "#041E42")) == true)
    }

    @Test("BOS gold does not need outline") func bosNoOutline() {
        #expect(NHLColor.needsVisibilityOutline(Color(hex: "#FFB81C")) == false)
    }

    @Test("NYR royal blue does not need outline") func nyrNoOutline() {
        // NYR #0038A8 lum ~0.057 — above 0.015 threshold
        #expect(NHLColor.needsVisibilityOutline(Color(hex: "#0038A8")) == false)
    }

    @Test("STL blue does not need outline") func stlNoOutline() {
        // STL #002F87 lum ~0.038
        #expect(NHLColor.needsVisibilityOutline(Color(hex: "#002F87")) == false)
    }
}

// MARK: - collisionResolve (via badgeColors)

@Suite("NHLColor.badgeColors — collision rule")
struct CollisionTests {

    @Test("BOS vs NYR — distinct primaries, no swap") func bosVsNyr() {
        let (home, away, _) = NHLColor.badgeColors(
            homePrimary: "#FFB81C", homeSecondary: "#000000",
            awayPrimary: "#0038A8", awaySecondary: "#CE1126"
        )
        // gold vs blue: distinct, no swap
        let dist = NHLColor.rgbDistance(home, away)
        #expect(dist >= NHLColor.collisionThreshold)
    }

    @Test("BOS home vs PIT away — both-fail: gold fails on white, home flips to black") func bosHomePitAway() {
        // BOS gold #FFB81C vs PIT gold #FCB514 — collision fires.
        // Both secondaries #000000 → both-fail. White tried: gold on white = 1.7:1 < 3.0 → fails.
        // Home returns its secondary (#000000) with outline; homePrimaryText = false.
        let (home, away, homePrimaryText) = NHLColor.badgeColors(
            homePrimary: "#FFB81C", homeSecondary: "#000000",
            awayPrimary: "#FCB514", awaySecondary: "#000000"
        )
        #expect(NHLColor.needsVisibilityOutline(home))           // home badge = black, needs outline
        #expect(!NHLColor.needsVisibilityOutline(away))           // away badge = gold, no outline
        #expect(!homePrimaryText)                                 // gold text flagged via isInvertedHome, not this
    }

    @Test("CHI home vs NJD away — both-fail: red passes on white, home flips to white") func chiHomeNjdAway() {
        // CHI red #CF0A2C vs NJD red #CE1126 — collision fires.
        // Both secondaries #000000 → both-fail. White tried: red on white ~5.6:1 ≥ 3.0 → succeeds.
        // Home returns white; homePrimaryText = true so caller shows primary (red) as text.
        let (home, away, homePrimaryText) = NHLColor.badgeColors(
            homePrimary: "#CF0A2C", homeSecondary: "#000000",
            awayPrimary: "#CE1126", awaySecondary: "#000000"
        )
        #expect(abs(home.relativeLuminance - 1.0) < 0.01)        // home badge = white
        #expect(!NHLColor.needsVisibilityOutline(away))           // away badge = red, no outline
        #expect(homePrimaryText)                                  // caller uses red primary as text
    }

    @Test("DET home vs CHI away — bidirectional flip: home flips to white via secondary") func detHomeChiAway() {
        // DET red #CE1126 vs CHI red #CF0A2C — collision fires.
        // CHI secondary #000000 too dark → try DET secondary #FFFFFF → viable (lum 1.0).
        // Home flips to white via Level 3 bidirectional; away keeps red primary.
        // homePrimaryText = false here because DET secondary itself is white (not the both-fail path).
        let (home, away, _) = NHLColor.badgeColors(
            homePrimary: "#CE1126", homeSecondary: "#FFFFFF",
            awayPrimary: "#CF0A2C", awaySecondary: "#000000"
        )
        #expect(abs(home.relativeLuminance - 1.0) < 0.01)        // home = white (#FFFFFF)
        #expect(away.relativeLuminance > 0.1)                    // away = red primary
    }

    @Test("NYR vs NYI — similar blues, away uses orange secondary") func nyrVsNyi() {
        // NYR #0038A8 vs NYI #003087 — both deep blue (collision fires).
        // NYI secondary #FC4C02 (orange, lum ~0.26) is light enough → swap succeeds.
        let (_, away, _) = NHLColor.badgeColors(
            homePrimary: "#0038A8", homeSecondary: "#CE1126",
            awayPrimary: "#003087", awaySecondary: "#FC4C02"
        )
        #expect(away.relativeLuminance > 0.1) // orange, not dark blue
    }

    @Test("EDM vs FLA — both navy primaries collide, FLA swaps to red secondary") func edmVsFlaNavyCollision() {
        // Both #041E42 navy — identical primaries (max collision). FLA secondary
        // #C8102E (red, lum ~0.14) is well above the threshold → swap succeeds.
        let (home, away, _) = NHLColor.badgeColors(
            homePrimary: "#041E42", homeSecondary: "#FC4C02",
            awayPrimary: "#041E42", awaySecondary: "#C8102E"
        )
        #expect(away.relativeLuminance > NHLColor.darkPrimaryLuminanceThreshold)
        _ = home // home keeps navy primary
    }
}

// MARK: - badgeTextColor

@Suite("NHLColor.badgeTextColor")
struct BadgeTextColorTests {

    @Test("legible secondary on dark fill → secondary text (VGK gold on steel)") func vgkSecondaryOnDark() {
        // VGK steel-grey #333F48 fill, gold #B4975A secondary — gold clears the
        // contrast floor, so the tricode picks up the team's second color.
        let fill = Color(hex: "#333F48")
        let secondary = Color(hex: "#B4975A")
        let text = NHLColor.badgeTextColor(fill: fill, secondary: secondary)
        #expect(UIColor(text) == UIColor(secondary))
    }

    @Test("light fill → secondary text") func lightFill() {
        let fill = Color(hex: "#FFB81C") // BOS gold — luminance > 0.5
        let secondary = Color(hex: "#000000")
        let text = NHLColor.badgeTextColor(fill: fill, secondary: secondary)
        #expect(UIColor(text) == UIColor(secondary))
    }

    @Test("illegible secondary on dark fill → white fallback (NYR red on blue)") func nyrIllegibleSecondary() {
        // NYR royal blue #0038A8 fill, red #CE1126 secondary — red doesn't clear
        // the contrast floor on blue, so it falls back to the more legible white.
        let fill = Color(hex: "#0038A8")
        let text = NHLColor.badgeTextColor(fill: fill, secondary: Color(hex: "#CE1126"))
        #expect(UIColor(text) == UIColor(.white))
    }

    @Test("secondary equals fill → legible b/w fallback") func secondaryEqualsFill() {
        // When fill and secondary are the same color, contrast ratio is 1:1 —
        // below the 3:1 floor — so badgeTextColor falls back to white or black.
        // On a light fill (#A2AAAD) black has higher contrast than white.
        let fill = Color(hex: "#A2AAAD")
        let text = NHLColor.badgeTextColor(fill: fill, secondary: Color(hex: "#A2AAAD"))
        #expect(UIColor(text) == UIColor(.black))
    }

    @Test("secondary equals fill, primary contrasts → primary text (DET on white)") func primaryFallbackOnWhite() {
        // DET bidirectional flip: fill = white (#FFFFFF), secondary = white (same → 1:1, fails).
        // Primary red #CE1126 is 5.6:1 on white — clears the 3:1 floor — so it's returned.
        let text = NHLColor.badgeTextColor(
            fill: Color(hex: "#FFFFFF"),
            secondary: Color(hex: "#FFFFFF"),
            primary: Color(hex: "#CE1126")
        )
        #expect(UIColor(text) == UIColor(Color(hex: "#CE1126")))
    }
}

// MARK: - ContentState.winnerTricode

@Suite("ContentState.winnerTricode")
struct WinnerTricodeTests {

    @Test("home wins → home tricode") func homeWins() {
        let state = FirepowerActivityAttributes.ContentState(
            homeScore: 4, awayScore: 2, gameState: "Final"
        )
        #expect(state.winnerTricode(homeTeam: "BOS", awayTeam: "NYR") == "BOS")
    }

    @Test("away wins → away tricode") func awayWins() {
        let state = FirepowerActivityAttributes.ContentState(
            homeScore: 1, awayScore: 3, gameState: "Final"
        )
        #expect(state.winnerTricode(homeTeam: "BOS", awayTeam: "NYR") == "NYR")
    }

    @Test("not ended → nil") func notEnded() {
        let state = FirepowerActivityAttributes.ContentState(
            homeScore: 2, awayScore: 1, gameState: "14:32 left, 2nd period"
        )
        #expect(state.winnerTricode(homeTeam: "BOS", awayTeam: "NYR") == nil)
    }
}

// MARK: - pinnedTricode resolution (unit-tested here as pure logic)

@Suite("pinnedTricode resolution")
struct PinnedTricodeTests {

    func resolve(home: String, away: String, pinned: Set<String>) -> String? {
        if pinned.contains(home) { return home }
        if pinned.contains(away) { return away }
        return nil  // caller falls back to home
    }

    @Test("pinned = home → home") func pinnedHome() {
        #expect(resolve(home: "BOS", away: "NYR", pinned: ["BOS"]) == "BOS")
    }

    @Test("pinned = away → away") func pinnedAway() {
        #expect(resolve(home: "BOS", away: "NYR", pinned: ["NYR"]) == "NYR")
    }

    @Test("neither pinned → nil (caller uses home)") func neitherPinned() {
        #expect(resolve(home: "BOS", away: "NYR", pinned: ["TOR"]) == nil)
    }

    @Test("both pinned → home wins (priority)") func bothPinned() {
        #expect(resolve(home: "BOS", away: "NYR", pinned: ["BOS", "NYR"]) == "BOS")
    }

    @Test("empty pinned → nil") func emptyPinned() {
        #expect(resolve(home: "BOS", away: "NYR", pinned: []) == nil)
    }
}

// MARK: - ContentState Codable roundtrip [REGRESSION]

@Suite("ContentState Codable roundtrip")
struct ContentStateCodableTests {

    @Test("roundtrip preserves all fields") func roundtrip() throws {
        let original = FirepowerActivityAttributes.ContentState(
            homeScore: 3,
            awayScore: 1,
            homeXG: 2.7,
            awayXG: 1.2,
            gameState: "08:41 left, 3rd period",
            eventType: "goal",
            eventDetail: "Marchand",
            eventTeam: "BOS"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            FirepowerActivityAttributes.ContentState.self, from: data
        )
        #expect(decoded.homeScore == original.homeScore)
        #expect(decoded.awayScore == original.awayScore)
        #expect(abs(decoded.homeXG - original.homeXG) < 0.001)
        #expect(abs(decoded.awayXG - original.awayXG) < 0.001)
        #expect(decoded.gameState == original.gameState)
        #expect(decoded.eventType == original.eventType)
        #expect(decoded.eventDetail == original.eventDetail)
        #expect(decoded.eventTeam == original.eventTeam)
    }

    @Test("nil optional fields decode cleanly") func nilFields() throws {
        let original = FirepowerActivityAttributes.ContentState(
            homeScore: 0, awayScore: 0, gameState: ""
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            FirepowerActivityAttributes.ContentState.self, from: data
        )
        #expect(decoded.eventType == nil)
        #expect(decoded.eventDetail == nil)
        #expect(decoded.eventTeam == nil)
        #expect(decoded.isPregame)
    }

    @Test("new + old fields together decode without crash") func backwardCompatNewAndOld() throws {
        let json = """
        {
          "homeScore": 2,
          "awayScore": 1,
          "homeXG": 2.4,
          "awayXG": 1.8,
          "gameState": "Final",
          "lastEvent": "Goal scored",
          "eventType": "goal",
          "eventDetail": "",
          "eventTeam": "BOS"
        }
        """.data(using: .utf8)!
        let state = try JSONDecoder().decode(
            FirepowerActivityAttributes.ContentState.self, from: json
        )
        #expect(state.homeScore == 2)
        #expect(state.isEnded)
        // New structured field wins over legacy
        #expect(state.resolvedEventType == "goal")
        #expect(state.resolvedEventTeam == "BOS")
    }

    @Test("old backend (lastEvent only) synthesises eventType via resolvedEventType") func legacyBackendFallback() throws {
        // Old backend only sends lastEvent; eventType/eventTeam absent.
        let json = """
        {
          "homeScore": 3,
          "awayScore": 2,
          "homeXG": 2.9,
          "awayXG": 2.1,
          "gameState": "02:14 left, 3rd period",
          "lastEvent": "Goal scored"
        }
        """.data(using: .utf8)!
        let state = try JSONDecoder().decode(
            FirepowerActivityAttributes.ContentState.self, from: json
        )
        // resolvedEventType falls back to legacy synthesis
        #expect(state.eventType == nil)
        #expect(state.resolvedEventType == "goal")
        // No team info in legacy path
        #expect(state.resolvedEventTeam == nil)
        // No scorer detail in legacy path
        #expect(state.resolvedEventDetail == nil)
    }

    @Test("old backend penalty synthesises correctly") func legacyPenaltyFallback() throws {
        let json = """
        {
          "homeScore": 0,
          "awayScore": 0,
          "homeXG": 0.3,
          "awayXG": 0.1,
          "gameState": "08:45 left, 1st period",
          "lastEvent": "Penalty - Tripping"
        }
        """.data(using: .utf8)!
        let state = try JSONDecoder().decode(
            FirepowerActivityAttributes.ContentState.self, from: json
        )
        #expect(state.resolvedEventType == "penalty")
    }

    @Test("old backend non-actionable event returns nil resolvedEventType") func legacyUnknownEvent() throws {
        let json = """
        {
          "homeScore": 1, "awayScore": 0,
          "homeXG": 1.2, "awayXG": 0.8,
          "gameState": "05:00 left, 2nd period",
          "lastEvent": "Shot blocked"
        }
        """.data(using: .utf8)!
        let state = try JSONDecoder().decode(
            FirepowerActivityAttributes.ContentState.self, from: json
        )
        #expect(state.resolvedEventType == nil)
    }
}
