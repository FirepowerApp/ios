import SwiftUI

// TodayView — the main app screen for v2.
//
// Layout:
//   "Pinned Teams" section  → games for user's pinned teams (sorted by start time)
//   "All Games" section     → everything else today
//   Empty state             → when no games at all
//
// Pull-to-refresh fetches the NHL Stats API.
// Gear icon → SettingsView sheet.

struct TodayView: View {

    @StateObject private var store = ScheduleStore()
    @StateObject private var activityManager = LiveActivityManager()
    @ObservedObject private var prefs = UserPreferences.shared

    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let error = store.fetchError, store.games.isEmpty {
                    errorState(error)
                } else if store.games.isEmpty && !store.isLoading {
                    #if DEBUG
                    ScrollView {
                        LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                            debugSection
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    #else
                    emptyState
                    #endif
                } else {
                    gameList
                }
            }
            .navigationTitle("Tonight")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .refreshable {
                await store.refresh()
                await scheduleNotifications()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
        .task {
            await store.refreshIfStale()
            await scheduleNotifications()
            activityManager.checkAuthorization()
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    // MARK: - Game list

    private var gameList: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                pinnedSection
                allGamesSection
                #if DEBUG
                debugSection
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private var pinnedSection: some View {
        let pinned = store.pinnedGames(for: prefs.pinnedTeams)
        if !prefs.pinnedTeams.isEmpty || !pinned.isEmpty {
            Section {
                if pinned.isEmpty {
                    Text("No pinned teams play today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(pinned) { game in
                        GameRowView(game: game, activityManager: activityManager, prefs: prefs)
                    }
                }
            } header: {
                sectionHeader("Pinned Teams", systemImage: "pin.fill")
            }
        }
    }

    @ViewBuilder
    private var allGamesSection: some View {
        let others = store.otherGames(excluding: prefs.pinnedTeams)
        if !others.isEmpty {
            Section {
                ForEach(others) { game in
                    GameRowView(game: game, activityManager: activityManager, prefs: prefs)
                }
            } header: {
                sectionHeader(prefs.pinnedTeams.isEmpty ? "Today's Games" : "Other Games",
                              systemImage: "sportscourt")
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .background(Color(.systemGroupedBackground))
    }

    // MARK: - Empty / error states

    // MARK: - Debug section (DEBUG builds only)

#if DEBUG
    private var debugSection: some View {
        Section {
            DebugLiveActivityControls(activityManager: activityManager)
        } header: {
            sectionHeader("Debug", systemImage: "hammer.fill")
        }
    }
#endif

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sportscourt")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No games today")
                .font(.title3.weight(.medium))
            Text("Pull down to refresh")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Couldn't load schedule")
                .font(.title3.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Pull down to retry")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Notification deep link

    // Pre-game notification taps deliver a URL scheme:
    //   firepower://start?gameID=X&homeTeam=Y&awayTeam=Z
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "firepower", url.host == "start" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        var params: [String: String] = [:]
        for item in items { if let v = item.value { params[item.name] = v } }

        guard let gameID   = params["gameID"],
              let homeTeam = params["homeTeam"],
              let awayTeam = params["awayTeam"] else { return }

        Task {
            await activityManager.startActivity(homeTeam: homeTeam, awayTeam: awayTeam, gameID: gameID)
        }
    }

    // MARK: - Notification scheduling helper

    private func scheduleNotifications() async {
        await NotificationManager.scheduleDailySummary(games: store.games, prefs: prefs)
        await NotificationManager.schedulePregameAlerts(games: store.games, prefs: prefs)
    }
}

#Preview {
    TodayView()
}
