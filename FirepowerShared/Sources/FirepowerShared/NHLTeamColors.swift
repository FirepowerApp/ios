import Foundation

// NHLTeamColors — team palette for all 32 NHL franchises.
//
// Used by both the app and the widget extension for badge colors.
// Channel IDs (APNs-only concern) stay in the app-target NHLTeams.swift.
//
// Source of truth: DESIGN.md — "primaryColor" is the badge fill color first choice;
// "secondaryColor" is the fallback for dark-primary guard and collision resolution.

public struct NHLTeamColors {
    public let tricode: String
    public let primaryColor: String    // hex e.g. "#FFB81C"
    public let secondaryColor: String  // hex e.g. "#000000"

    public static func colors(for tricode: String) -> NHLTeamColors? {
        all.first { $0.tricode.uppercased() == tricode.uppercased() }
    }

    public static let all: [NHLTeamColors] = [
        NHLTeamColors(tricode: "ANA", primaryColor: "#F47A38", secondaryColor: "#B9975B"),
        NHLTeamColors(tricode: "BOS", primaryColor: "#FFB81C", secondaryColor: "#000000"),
        NHLTeamColors(tricode: "BUF", primaryColor: "#003087", secondaryColor: "#FCB514"),
        NHLTeamColors(tricode: "CGY", primaryColor: "#C8102E", secondaryColor: "#F1BE48"),
        NHLTeamColors(tricode: "CAR", primaryColor: "#CC0000", secondaryColor: "#FFFFFF"),
        NHLTeamColors(tricode: "CHI", primaryColor: "#CF0A2C", secondaryColor: "#000000"),
        NHLTeamColors(tricode: "COL", primaryColor: "#6F263D", secondaryColor: "#236192"),
        NHLTeamColors(tricode: "CBJ", primaryColor: "#002654", secondaryColor: "#CE1126"),
        NHLTeamColors(tricode: "DAL", primaryColor: "#006847", secondaryColor: "#FFFFFF"),
        NHLTeamColors(tricode: "DET", primaryColor: "#CE1126", secondaryColor: "#FFFFFF"),
        NHLTeamColors(tricode: "EDM", primaryColor: "#041E42", secondaryColor: "#FC4C02"),
        NHLTeamColors(tricode: "FLA", primaryColor: "#041E42", secondaryColor: "#C8102E"),
        NHLTeamColors(tricode: "LAK", primaryColor: "#111111", secondaryColor: "#A2AAAD"),
        NHLTeamColors(tricode: "MIN", primaryColor: "#154734", secondaryColor: "#DDCBA4"),
        NHLTeamColors(tricode: "MTL", primaryColor: "#AF1E2D", secondaryColor: "#192168"),
        NHLTeamColors(tricode: "NSH", primaryColor: "#041E42", secondaryColor: "#FFB81C"),
        NHLTeamColors(tricode: "NJD", primaryColor: "#CE1126", secondaryColor: "#000000"),
        NHLTeamColors(tricode: "NYI", primaryColor: "#003087", secondaryColor: "#FC4C02"),
        NHLTeamColors(tricode: "NYR", primaryColor: "#0038A8", secondaryColor: "#CE1126"),
        NHLTeamColors(tricode: "OTT", primaryColor: "#C52032", secondaryColor: "#C69214"),
        NHLTeamColors(tricode: "PHI", primaryColor: "#F74902", secondaryColor: "#000000"),
        NHLTeamColors(tricode: "PIT", primaryColor: "#FCB514", secondaryColor: "#000000"),
        NHLTeamColors(tricode: "SJS", primaryColor: "#006D75", secondaryColor: "#FFFFFF"),
        NHLTeamColors(tricode: "SEA", primaryColor: "#001628", secondaryColor: "#99D9D9"),
        NHLTeamColors(tricode: "STL", primaryColor: "#002F87", secondaryColor: "#FCB514"),
        NHLTeamColors(tricode: "TBL", primaryColor: "#002868", secondaryColor: "#FFFFFF"),
        NHLTeamColors(tricode: "TOR", primaryColor: "#003E7E", secondaryColor: "#FFFFFF"),
        NHLTeamColors(tricode: "UTA", primaryColor: "#1F3765", secondaryColor: "#6CACE4"),
        NHLTeamColors(tricode: "VAN", primaryColor: "#00205B", secondaryColor: "#00843D"),
        NHLTeamColors(tricode: "VGK", primaryColor: "#333F48", secondaryColor: "#B4975A"),
        NHLTeamColors(tricode: "WSH", primaryColor: "#041E42", secondaryColor: "#C8102E"),
        NHLTeamColors(tricode: "WPG", primaryColor: "#041E42", secondaryColor: "#AC162C"),
    ]
}
