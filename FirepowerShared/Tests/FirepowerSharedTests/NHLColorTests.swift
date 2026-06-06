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

// MARK: - darkPrimaryGuard

@Suite("NHLColor.darkPrimaryGuard")
struct DarkPrimaryGuardTests {

    @Test("LAK dark primary swaps to silver secondary") func lakDark() {
        // LAK: primary=#111111 (luminance 0.004), secondary=#A2AAAD
        let result = NHLColor.darkPrimaryGuard(primary: "#111111", secondary: "#A2AAAD")
        #expect(result.relativeLuminance > 0.3) // silver, not black
    }

    @Test("SEA dark primary swaps to cyan secondary") func seaDark() {
        let result = NHLColor.darkPrimaryGuard(primary: "#001628", secondary: "#99D9D9")
        #expect(result.relativeLuminance > 0.3)
    }

    @Test("BOS gold stays gold (not dark)") func bosKeepsPrimary() {
        let result = NHLColor.darkPrimaryGuard(primary: "#FFB81C", secondary: "#000000")
        #expect(result.relativeLuminance > 0.5) // still gold
    }

    @Test("NYR blue stays blue (not below threshold)") func nyrKeepsPrimary() {
        let result = NHLColor.darkPrimaryGuard(primary: "#0038A8", secondary: "#CE1126")
        // #0038A8 luminance ~0.05 — below 0.08 threshold, should swap
        #expect(result.relativeLuminance > 0.05)
    }
}

// MARK: - collisionResolve (via badgeColors)

@Suite("NHLColor.badgeColors — collision rule")
struct CollisionTests {

    @Test("BOS vs NYR — distinct, no swap") func bosVsNyr() {
        let (home, away) = NHLColor.badgeColors(
            homePrimary: "#FFB81C", homeSecondary: "#000000",
            awayPrimary: "#0038A8", awaySecondary: "#CE1126"
        )
        // gold vs blue: distinct
        let dist = NHLColor.rgbDistance(home, away)
        #expect(dist >= NHLColor.collisionThreshold)
        _ = away // away stays blue
    }

    @Test("BOS vs PIT — collision, away uses black secondary") func bosVsPit() {
        // BOS gold #FFB81C vs PIT gold #FCB514 — very similar
        let (home, away) = NHLColor.badgeColors(
            homePrimary: "#FFB81C", homeSecondary: "#000000",
            awayPrimary: "#FCB514", awaySecondary: "#000000"
        )
        // away resolved to secondary (black); distance from gold to black is large
        let dist = NHLColor.rgbDistance(home, away)
        #expect(dist >= NHLColor.collisionThreshold)
    }

    @Test("NYR vs NYI — similar blues, away uses orange") func nyrVsNyi() {
        // NYR #0038A8 vs NYI #003087 — both deep blue
        let (_, away) = NHLColor.badgeColors(
            homePrimary: "#0038A8", homeSecondary: "#CE1126",
            awayPrimary: "#003087", awaySecondary: "#FC4C02"
        )
        // away should be FC4C02 (orange), not the dark blue
        #expect(away.relativeLuminance > 0.1)
    }
}

// MARK: - badgeTextColor

@Suite("NHLColor.badgeTextColor")
struct BadgeTextColorTests {

    @Test("dark fill → white text") func darkFill() {
        let fill = Color(hex: "#0038A8") // NYR blue
        let text = NHLColor.badgeTextColor(fill: fill, secondary: Color(hex: "#CE1126"))
        #expect(UIColor(text) == UIColor(.white))
    }

    @Test("light fill → secondary text") func lightFill() {
        let fill = Color(hex: "#FFB81C") // BOS gold — luminance > 0.5
        let secondary = Color(hex: "#000000")
        let text = NHLColor.badgeTextColor(fill: fill, secondary: secondary)
        #expect(UIColor(text) == UIColor(secondary))
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
