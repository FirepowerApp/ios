import Foundation
import SwiftUI
import Combine

@MainActor
final class ScheduleStore: ObservableObject {

    @Published private(set) var games: [NHLGame] = []
    @Published private(set) var isLoading = false
    @Published private(set) var fetchError: String?
    @Published private(set) var lastFetchDate: Date?

    static let gamesKey = "cachedGames"
    static let dateKey  = "cachedGamesDate"

    /// Foreground refresh only refetches when the last successful fetch is
    /// older than this. Keeps the list from going stale across a whole evening
    /// while avoiding a network call on every single foreground.
    static let freshnessWindow: TimeInterval = 5 * 60

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadCache()
    }

    func refresh() async {
        isLoading = true
        fetchError = nil
        defer { isLoading = false }
        do {
            let fetched = try await NHLScheduleClient.fetchTodayGames()
            let now = Date()
            games = fetched
            lastFetchDate = now
            Self.writeCache(fetched, at: now, into: defaults)
        } catch {
            fetchError = "Couldn't load schedule"
        }
    }

    /// Called on every foreground (via TodayView's scenePhase reconcile).
    ///
    ///   lastFetchDate nil ........................ refresh
    ///   last fetch day != today .................. clear games, refresh
    ///                                               (never render yesterday's
    ///                                               games while refetching —
    ///                                               a failed refetch then shows
    ///                                               the error state, not stale
    ///                                               games)
    ///   today, older than freshnessWindow ........ refresh, keep current games
    ///                                               on screen while it runs
    ///   today, within freshnessWindow ............ no-op
    func refreshIfStale() async {
        guard !isLoading else { return }
        guard let last = lastFetchDate else {
            await refresh()
            return
        }

        if !Calendar.current.isDateInToday(last) {
            games = []
            lastFetchDate = nil
            await refresh()
            return
        }
        if Date().timeIntervalSince(last) > Self.freshnessWindow {
            await refresh()
        }
    }

    /// Adopts a cache written by BackgroundTaskManager's BGAppRefreshTask while
    /// this process was suspended. Without this, a successful background
    /// refresh is invisible until the next cold launch. Guarded on the
    /// persisted timestamp being strictly newer than what we already have, so
    /// this is a no-op on most foregrounds (not every one).
    func reloadCacheIfNewer() {
        guard
            let dateData = defaults.data(forKey: Self.dateKey),
            let date = try? JSONDecoder().decode(Date.self, from: dateData),
            Calendar.current.isDateInToday(date),
            lastFetchDate.map({ date > $0 }) ?? true,
            let gamesData = defaults.data(forKey: Self.gamesKey),
            let cached = try? JSONDecoder().decode([NHLGame].self, from: gamesData)
        else { return }
        games = cached
        lastFetchDate = date
    }

    // MARK: - Filtered views

    func pinnedGames(for pinned: Set<String>) -> [NHLGame] {
        games.filter { $0.pinnedTricode(from: pinned) != nil }
            .sorted { lhs, rhs in
                (lhs.startDate ?? .distantFuture) < (rhs.startDate ?? .distantFuture)
            }
    }

    func otherGames(excluding pinned: Set<String>) -> [NHLGame] {
        games.filter { $0.pinnedTricode(from: pinned) == nil }
            .sorted { lhs, rhs in
                (lhs.startDate ?? .distantFuture) < (rhs.startDate ?? .distantFuture)
            }
    }

    // MARK: - Cache

    private func loadCache() {
        guard
            let gamesData = defaults.data(forKey: Self.gamesKey),
            let dateData  = defaults.data(forKey: Self.dateKey),
            let date      = try? JSONDecoder().decode(Date.self, from: dateData),
            Calendar.current.isDateInToday(date),
            let cached    = try? JSONDecoder().decode([NHLGame].self, from: gamesData)
        else { return }
        games = cached
        lastFetchDate = date
    }

    /// The single writer of the cached-schedule format — used by both `refresh()`
    /// and BackgroundTaskManager's BGAppRefreshTask, so there is exactly one place
    /// that knows the on-disk shape.
    ///
    /// `date` must be the caller's fetch timestamp, never a freshly-minted
    /// `Date()` — persisting a later timestamp than the in-memory `lastFetchDate`
    /// would make `reloadCacheIfNewer()`'s "is the cache newer?" check always
    /// true, decoding and reassigning the full games array on every foreground.
    static func writeCache(_ games: [NHLGame], at date: Date, into defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(games) else {
            print("ScheduleStore: FAILED to encode \(games.count) games for cache")
            return
        }
        defaults.set(data, forKey: gamesKey)
        guard let dateData = try? JSONEncoder().encode(date) else {
            print("ScheduleStore: FAILED to encode cache date \(date)")
            return
        }
        defaults.set(dateData, forKey: dateKey)
    }
}
