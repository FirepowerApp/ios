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
    // Resolved at build time: debug → sandbox APNs, release → production APNs.
    let channelId: String

    var id: String { tricode }
    var logoAssetName: String { tricode.lowercased() }
}

// MARK: - Channel IDs

private extension NHLTeam {

    // Sandbox APNs channel IDs (debug builds only).
    // Create via App Store Connect → Push Notifications → Broadcast → Development.
    static let debugChannelIds: [String: String] = [
        "ANA": "PHP5yU/pEfEAAMK1EJkzxg==",
        "BUF": "iqg6AFASEfEAAL4dEtalNQ==",
        "CAR": "5GIeaFVyEfEAAObg6VLmpQ==",
        "COL": "+pSGy0vgEfEAAKqhstn/Jg==",
        "MTL": "uj76s1ikEfEAAObg6VLmpQ==",
        "VGK": "CVEIvlilEfEAAK6J2RjHtg==",
        "CHI": "",
        "BOS": "",
        "CBJ": "",
        "CGY": "",
        "DAL": "",
        "DET": "",
        "EDM": "",
        "FLA": "",
        "LAK": "",
        "MIN": "",
        "NJD": "",
        "NSH": "",
        "NYI": "",
        "NYR": "",
        "OTT": "",
        "PHI": "",
        "PIT": "",
        "SEA": "",
        "SJS": "",
        "STL": "",
        "TBL": "",
        "TOR": "",
        "UTA": "",
        "VAN": "",
        "WPG": "",
        "WSH": ""
    ]

    // Production APNs channel IDs (release/TestFlight/App Store builds).
    // Create via App Store Connect → Push Notifications → Broadcast → Production.
    static let prodChannelIds: [String: String] = [
        "CAR": "d4E+F1ikEfEAAF7OhT1omw==",
        "MTL": "GOmex1ilEfEAAOYo81Crcg==",
        "VGK": "Y8GZXlikEfEAAE4quYgbSQ==",
        "COL": "S7cBYlilEfEAADY6cc28lw==",
        "CHI": "VeHR2HNPEfEAAIIz9BtJIg==",
        "ANA": "UhYmnn8mEfEAAOYc0Q7CQQ==",
        "BOS": "+YMYln8mEfEAADq3u4xYzw==",
        "BUF": "Au/kwn8nEfEAAOYc0Q7CQQ==",
        "CBJ": "Cd+IhX8nEfEAAOK+11eG0w==",
        "CGY": "ETvY2H8nEfEAAFr0zqCBeA==",
        "DAL": "GNBrYX8nEfEAALJMNogb7Q==",
        "DET": "IwHOp38nEfEAADq3u4xYzw==",
        "EDM": "KeUc6H8nEfEAADq3u4xYzw==",
        "FLA": "Z9sW/X8pEfEAAOYc0Q7CQQ==",
        "LAK": "b92xa38pEfEAAOK+11eG0w==",
        "MIN": "eotUn38pEfEAAOYc0Q7CQQ==",
        "NJD": "g1DIan8pEfEAAC4RS0Xe8Q==",
        "NSH": "imyy238pEfEAAC4RS0Xe8Q==",
        "NYI": "kgA+TH8pEfEAAC4RS0Xe8Q==",
        "NYR": "miMsfn8pEfEAADq3u4xYzw==",
        "OTT": "oLgaDH8pEfEAAOK+11eG0w==",
        "PHI": "yMEWan8pEfEAAJYcSnrw9A==",
        "PIT": "z8aSq38pEfEAAJYcSnrw9A==",
        "SEA": "1tEcRn8pEfEAAD7+DDlNqw==",
        "SJS": "3qTJ0X8pEfEAAOYc0Q7CQQ==",
        "STL": "5Qj3Bn8pEfEAACopEMQCsQ==",
        "TBL": "7Sjk538pEfEAAFr0zqCBeA==",
        "TOR": "8yE1938pEfEAACopEMQCsQ==",
        "UTA": "+NY7bn8pEfEAAC4RS0Xe8Q==",
        "VAN": "/1iF5H8pEfEAAOYc0Q7CQQ==",
        "WPG": "BdfcOX8qEfEAACopEMQCsQ==",
        "WSH": "DMyFbX8qEfEAAJYcSnrw9A=="
    ]

    static func channelId(for tricode: String) -> String {
        #if DEBUG
        return debugChannelIds[tricode] ?? ""
        #else
        return prodChannelIds[tricode] ?? ""
        #endif
    }
}

// MARK: - All 32 teams

extension NHLTeam {

    static let all: [NHLTeam] = [
        //              tricode   name                          primary      secondary
        NHLTeam(tricode: "ANA", name: "Anaheim Ducks",          primaryColor: "#F47A38", secondaryColor: "#B9975B", channelId: channelId(for: "ANA")),
        NHLTeam(tricode: "BOS", name: "Boston Bruins",           primaryColor: "#FFB81C", secondaryColor: "#000000", channelId: channelId(for: "BOS")),
        NHLTeam(tricode: "BUF", name: "Buffalo Sabres",          primaryColor: "#003087", secondaryColor: "#FCB514", channelId: channelId(for: "BUF")),
        NHLTeam(tricode: "CGY", name: "Calgary Flames",          primaryColor: "#C8102E", secondaryColor: "#F1BE48", channelId: channelId(for: "CGY")),
        NHLTeam(tricode: "CAR", name: "Carolina Hurricanes",     primaryColor: "#CC0000", secondaryColor: "#FFFFFF", channelId: channelId(for: "CAR")),
        NHLTeam(tricode: "CHI", name: "Chicago Blackhawks",      primaryColor: "#CF0A2C", secondaryColor: "#000000", channelId: channelId(for: "CHI")),
        NHLTeam(tricode: "COL", name: "Colorado Avalanche",      primaryColor: "#6F263D", secondaryColor: "#236192", channelId: channelId(for: "COL")),
        NHLTeam(tricode: "CBJ", name: "Columbus Blue Jackets",   primaryColor: "#002654", secondaryColor: "#CE1126", channelId: channelId(for: "CBJ")),
        NHLTeam(tricode: "DAL", name: "Dallas Stars",            primaryColor: "#006847", secondaryColor: "#FFFFFF", channelId: channelId(for: "DAL")),
        NHLTeam(tricode: "DET", name: "Detroit Red Wings",       primaryColor: "#CE1126", secondaryColor: "#FFFFFF", channelId: channelId(for: "DET")),
        NHLTeam(tricode: "EDM", name: "Edmonton Oilers",         primaryColor: "#041E42", secondaryColor: "#FC4C02", channelId: channelId(for: "EDM")),
        NHLTeam(tricode: "FLA", name: "Florida Panthers",        primaryColor: "#041E42", secondaryColor: "#C8102E", channelId: channelId(for: "FLA")),
        NHLTeam(tricode: "LAK", name: "Los Angeles Kings",       primaryColor: "#111111", secondaryColor: "#A2AAAD", channelId: channelId(for: "LAK")),
        NHLTeam(tricode: "MIN", name: "Minnesota Wild",          primaryColor: "#154734", secondaryColor: "#DDCBA4", channelId: channelId(for: "MIN")),
        NHLTeam(tricode: "MTL", name: "Montréal Canadiens",      primaryColor: "#AF1E2D", secondaryColor: "#192168", channelId: channelId(for: "MTL")),
        NHLTeam(tricode: "NSH", name: "Nashville Predators",     primaryColor: "#041E42", secondaryColor: "#FFB81C", channelId: channelId(for: "NSH")),
        NHLTeam(tricode: "NJD", name: "New Jersey Devils",       primaryColor: "#CE1126", secondaryColor: "#000000", channelId: channelId(for: "NJD")),
        NHLTeam(tricode: "NYI", name: "New York Islanders",      primaryColor: "#003087", secondaryColor: "#FC4C02", channelId: channelId(for: "NYI")),
        NHLTeam(tricode: "NYR", name: "New York Rangers",        primaryColor: "#0038A8", secondaryColor: "#CE1126", channelId: channelId(for: "NYR")),
        NHLTeam(tricode: "OTT", name: "Ottawa Senators",         primaryColor: "#C52032", secondaryColor: "#C69214", channelId: channelId(for: "OTT")),
        NHLTeam(tricode: "PHI", name: "Philadelphia Flyers",     primaryColor: "#F74902", secondaryColor: "#000000", channelId: channelId(for: "PHI")),
        NHLTeam(tricode: "PIT", name: "Pittsburgh Penguins",     primaryColor: "#FCB514", secondaryColor: "#000000", channelId: channelId(for: "PIT")),
        NHLTeam(tricode: "SJS", name: "San Jose Sharks",         primaryColor: "#006D75", secondaryColor: "#FFFFFF", channelId: channelId(for: "SJS")),
        NHLTeam(tricode: "SEA", name: "Seattle Kraken",          primaryColor: "#001628", secondaryColor: "#99D9D9", channelId: channelId(for: "SEA")),
        NHLTeam(tricode: "STL", name: "St. Louis Blues",         primaryColor: "#002F87", secondaryColor: "#FCB514", channelId: channelId(for: "STL")),
        NHLTeam(tricode: "TBL", name: "Tampa Bay Lightning",     primaryColor: "#002868", secondaryColor: "#FFFFFF", channelId: channelId(for: "TBL")),
        NHLTeam(tricode: "TOR", name: "Toronto Maple Leafs",     primaryColor: "#003E7E", secondaryColor: "#FFFFFF", channelId: channelId(for: "TOR")),
        NHLTeam(tricode: "UTA", name: "Utah Hockey Club",        primaryColor: "#1F3765", secondaryColor: "#6CACE4", channelId: channelId(for: "UTA")),
        NHLTeam(tricode: "VAN", name: "Vancouver Canucks",       primaryColor: "#00205B", secondaryColor: "#00843D", channelId: channelId(for: "VAN")),
        NHLTeam(tricode: "VGK", name: "Vegas Golden Knights",    primaryColor: "#333F48", secondaryColor: "#B4975A", channelId: channelId(for: "VGK")),
        NHLTeam(tricode: "WSH", name: "Washington Capitals",     primaryColor: "#041E42", secondaryColor: "#C8102E", channelId: channelId(for: "WSH")),
        NHLTeam(tricode: "WPG", name: "Winnipeg Jets",           primaryColor: "#041E42", secondaryColor: "#AC162C", channelId: channelId(for: "WPG")),
    ]

    static func team(for tricode: String) -> NHLTeam? {
        all.first { $0.tricode.uppercased() == tricode.uppercased() }
    }
}
