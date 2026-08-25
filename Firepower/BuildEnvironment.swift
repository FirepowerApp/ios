import Foundation

/// Distinguishes Dev, TestFlight, and App Store production at runtime. iOS has
/// no Apple-documented API for "am I TestFlight" — the standard community trick
/// is the app-store receipt's filename (sandboxReceipt vs receipt). This is a
/// heuristic, not a guarantee, so resolution fails closed toward `.appStore`:
/// anything ambiguous is treated as production, so a bad guess only ever HIDES
/// offseason replay data, never exposes it to real users.
enum BuildEnvironment {
    case dev
    case testFlight
    case appStore

    static var current: BuildEnvironment {
        #if DEBUG
        return .dev
        #else
        return resolve(receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
        #endif
    }

    /// Pulled out as a pure function so the fail-closed resolution is testable
    /// without a real app bundle / receipt.
    static func resolve(receiptName: String?) -> BuildEnvironment {
        receiptName == "sandboxReceipt" ? .testFlight : .appStore
    }

    /// Offseason replayed games are shown only in Dev and TestFlight — never to
    /// real App Store users. This is the only behavior that varies by build
    /// environment; score sourcing and state sourcing do not (see
    /// NHLScheduleClient.fetchTodayGames).
    var showsReplayedGames: Bool {
        self != .appStore
    }
}
