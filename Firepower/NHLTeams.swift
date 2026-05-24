import Foundation

// NHLTeam: static configuration for all 32 NHL teams.
//
// channelId is the APNs channel ID for this team's Live Activity channel,
// stored as base64
//
// Architecture: the app is a pure APNs channel subscriber.
// There are no runtime calls to the Firepower backend.

struct NHLTeam: Identifiable, Equatable {
    let tricode: String
    let name: String
    let primaryColor: String    // hex, full-bleed background
    let secondaryColor: String  // hex, text + button tint

    // APNs channel ID for this team's Live Activity channel (base64).
    let channelId: String

    var id: String { tricode }
    var logoAssetName: String { tricode.lowercased() }
}

// MARK: - All 32 teams

extension NHLTeam {

    static let all: [NHLTeam] = [
        //              tricode   name                          primary      secondary    channelId
        NHLTeam(tricode: "ANA", name: "Anaheim Ducks",          primaryColor: "#F47A38", secondaryColor: "#B9975B", channelId: "PHP5yU/pEfEAAMK1EJkzxg=="),
        NHLTeam(tricode: "BOS", name: "Boston Bruins",           primaryColor: "#FFB81C", secondaryColor: "#000000", channelId: ""),
        NHLTeam(tricode: "BUF", name: "Buffalo Sabres",          primaryColor: "#003087", secondaryColor: "#FCB514", channelId: "iqg6AFASEfEAAL4dEtalNQ=="),
        NHLTeam(tricode: "CGY", name: "Calgary Flames",          primaryColor: "#C8102E", secondaryColor: "#F1BE48", channelId: ""),
        NHLTeam(tricode: "CAR", name: "Carolina Hurricanes",     primaryColor: "#CC0000", secondaryColor: "#FFFFFF", channelId: "5GIeaFVyEfEAAObg6VLmpQ=="),
        NHLTeam(tricode: "CHI", name: "Chicago Blackhawks",      primaryColor: "#CF0A2C", secondaryColor: "#000000", channelId: ""),
        NHLTeam(tricode: "COL", name: "Colorado Avalanche",      primaryColor: "#6F263D", secondaryColor: "#236192", channelId: "+pSGy0vgEfEAAKqhstn/Jg=="),
        NHLTeam(tricode: "CBJ", name: "Columbus Blue Jackets",   primaryColor: "#002654", secondaryColor: "#CE1126", channelId: ""),
        NHLTeam(tricode: "DAL", name: "Dallas Stars",            primaryColor: "#006847", secondaryColor: "#FFFFFF", channelId: ""),
        NHLTeam(tricode: "DET", name: "Detroit Red Wings",       primaryColor: "#CE1126", secondaryColor: "#FFFFFF", channelId: ""),
        NHLTeam(tricode: "EDM", name: "Edmonton Oilers",         primaryColor: "#041E42", secondaryColor: "#FC4C02", channelId: ""),
        NHLTeam(tricode: "FLA", name: "Florida Panthers",        primaryColor: "#041E42", secondaryColor: "#C8102E", channelId: ""),
        NHLTeam(tricode: "LAK", name: "Los Angeles Kings",       primaryColor: "#111111", secondaryColor: "#A2AAAD", channelId: ""),
        NHLTeam(tricode: "MIN", name: "Minnesota Wild",          primaryColor: "#154734", secondaryColor: "#DDCBA4", channelId: ""),
        NHLTeam(tricode: "MTL", name: "Montréal Canadiens",      primaryColor: "#AF1E2D", secondaryColor: "#192168", channelId: ""),
        NHLTeam(tricode: "NSH", name: "Nashville Predators",     primaryColor: "#041E42", secondaryColor: "#FFB81C", channelId: ""),
        NHLTeam(tricode: "NJD", name: "New Jersey Devils",       primaryColor: "#CE1126", secondaryColor: "#000000", channelId: ""),
        NHLTeam(tricode: "NYI", name: "New York Islanders",      primaryColor: "#003087", secondaryColor: "#FC4C02", channelId: ""),
        NHLTeam(tricode: "NYR", name: "New York Rangers",        primaryColor: "#0038A8", secondaryColor: "#CE1126", channelId: ""),
        NHLTeam(tricode: "OTT", name: "Ottawa Senators",         primaryColor: "#C52032", secondaryColor: "#C69214", channelId: ""),
        NHLTeam(tricode: "PHI", name: "Philadelphia Flyers",     primaryColor: "#F74902", secondaryColor: "#000000", channelId: ""),
        NHLTeam(tricode: "PIT", name: "Pittsburgh Penguins",     primaryColor: "#FCB514", secondaryColor: "#000000", channelId: ""),
        NHLTeam(tricode: "SJS", name: "San Jose Sharks",         primaryColor: "#006D75", secondaryColor: "#FFFFFF", channelId: ""),
        NHLTeam(tricode: "SEA", name: "Seattle Kraken",          primaryColor: "#001628", secondaryColor: "#99D9D9", channelId: ""),
        NHLTeam(tricode: "STL", name: "St. Louis Blues",         primaryColor: "#002F87", secondaryColor: "#FCB514", channelId: ""),
        NHLTeam(tricode: "TBL", name: "Tampa Bay Lightning",     primaryColor: "#002868", secondaryColor: "#FFFFFF", channelId: ""),
        NHLTeam(tricode: "TOR", name: "Toronto Maple Leafs",     primaryColor: "#003E7E", secondaryColor: "#FFFFFF", channelId: ""),
        NHLTeam(tricode: "UTA", name: "Utah Hockey Club",        primaryColor: "#1F3765", secondaryColor: "#6CACE4", channelId: ""),
        NHLTeam(tricode: "VAN", name: "Vancouver Canucks",       primaryColor: "#00205B", secondaryColor: "#00843D", channelId: ""),
        NHLTeam(tricode: "VGK", name: "Vegas Golden Knights",    primaryColor: "#333F48", secondaryColor: "#B4975A", channelId: ""),
        NHLTeam(tricode: "WSH", name: "Washington Capitals",     primaryColor: "#041E42", secondaryColor: "#C8102E", channelId: ""),
        NHLTeam(tricode: "WPG", name: "Winnipeg Jets",           primaryColor: "#041E42", secondaryColor: "#AC162C", channelId: ""),
    ]

    static func team(for tricode: String) -> NHLTeam? {
        all.first { $0.tricode.uppercased() == tricode.uppercased() }
    }
}

