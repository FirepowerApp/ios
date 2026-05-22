import Foundation
import SwiftUI
import Combine

@MainActor
final class ScheduleStore: ObservableObject {

    @Published private(set) var games: [NHLGame] = []
    @Published private(set) var isLoading = false
    @Published private(set) var fetchError: String?
    @Published private(set) var lastFetchDate: Date?

    private let gamesKey    = "cachedGames"
    private let dateKey     = "cachedGamesDate"

    init() {
        loadCache()
    }

    func refresh() async {
        isLoading = true
        fetchError = nil
        defer { isLoading = false }
        do {
            let fetched = try await NHLScheduleClient.fetchTodayGames()
            games = fetched
            lastFetchDate = Date()
            save(fetched)
        } catch {
            fetchError = "Couldn't load schedule"
        }
    }

    func refreshIfStale() async {
        guard !isLoading else { return }
        let stale = lastFetchDate.map { !Calendar.current.isDateInToday($0) } ?? true
        if stale { await refresh() }
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
            let gamesData = UserDefaults.standard.data(forKey: gamesKey),
            let dateData  = UserDefaults.standard.data(forKey: dateKey),
            let date      = try? JSONDecoder().decode(Date.self, from: dateData),
            Calendar.current.isDateInToday(date),
            let cached    = try? JSONDecoder().decode([NHLGame].self, from: gamesData)
        else { return }
        games = cached
        lastFetchDate = date
    }

    private func save(_ games: [NHLGame]) {
        if let data = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(data, forKey: gamesKey)
        }
        if let dateData = try? JSONEncoder().encode(Date()) {
            UserDefaults.standard.set(dateData, forKey: dateKey)
        }
    }
}
