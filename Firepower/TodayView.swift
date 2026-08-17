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

    @StateObject private var store: ScheduleStore
    @StateObject private var activityManager = LiveActivityManager()
    @ObservedObject private var prefs = UserPreferences.shared

    init() {
        _store = StateObject(wrappedValue: ScheduleStore())
    }

    #if DEBUG
    init(previewStore: ScheduleStore) {
        _store = StateObject(wrappedValue: previewStore)
    }
    #endif

    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if let error = store.fetchError, store.games.isEmpty {
                    errorState(error)
                } else if store.games.isEmpty && store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.games.isEmpty && !store.isLoading {
                    #if DEBUG
                    ScrollView {
                        LazyVStack(spacing: 16, pinnedViews: []) {
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
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
            await reconcile()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await reconcile() }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    // MARK: - Game list

    // Ticks every 60s so the 4-hour Track gate opens on its own while the app
    // is foregrounded, without needing a relaunch or pull-to-refresh. This does
    // NOT refetch data — see ScheduleStore.freshnessWindow for that.
    private var gameList: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                LazyVStack(spacing: 16, pinnedViews: []) {
                    pinnedSection(now: context.date)
                    allGamesSection(now: context.date)
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
    }

    @ViewBuilder
    private func pinnedSection(now: Date) -> some View {
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
                        GameRowView(game: game, activityManager: activityManager, prefs: prefs, now: now)
                    }
                }
            } header: {
                sectionHeader("Pinned Teams", systemImage: "pin.fill")
            }
        }
    }

    @ViewBuilder
    private func allGamesSection(now: Date) -> some View {
        let others = store.otherGames(excluding: prefs.pinnedTeams)
        if !others.isEmpty {
            Section {
                ForEach(others) { game in
                    GameRowView(game: game, activityManager: activityManager, prefs: prefs, now: now)
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
    //   firepower://start?gameID=X&homeTeam=Y&awayTeam=Z&startTimeUTC=ISO8601
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "firepower", url.host == "start" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        var params: [String: String] = [:]
        for item in items { if let v = item.value { params[item.name] = v } }

        guard let gameID   = params["gameID"],
              let homeTeam = params["homeTeam"],
              let awayTeam = params["awayTeam"] else { return }

        let startTime = params["startTimeUTC"].flatMap { ISO8601DateFormatter().date(from: $0) }

        Task {
            await activityManager.startActivity(
                homeTeam: homeTeam, awayTeam: awayTeam, gameID: gameID, startTime: startTime)
        }
    }

    // MARK: - Notification scheduling helper

    private func scheduleNotifications() async {
        await NotificationManager.scheduleDailySummary(games: store.games, prefs: prefs)
        await NotificationManager.schedulePregameAlerts(games: store.games, prefs: prefs)
    }

    // MARK: - Reconcile

    /// Brings displayed state back in line with reality. Called from both
    /// `.task` (cold launch) and the scenePhase change to `.active` (resume),
    /// which means it can run twice in a row on cold launch — the scene can
    /// pass through .inactive before settling on .active.
    ///
    /// EVERY STEP BELOW MUST STAY IDEMPOTENT. That is what makes the double
    /// run harmless: refresh() sets isLoading synchronously before its first
    /// await (no double fetch), reloadCacheIfNewer() only acts on a strictly
    /// newer timestamp, rehydrate() is safe to call any number of times, and
    /// UNNotificationRequest replaces by identifier (no duplicate alerts). Do
    /// not add a step with side effects that compound across repeated calls.
    private func reconcile() async {
        store.reloadCacheIfNewer()
        await store.refreshIfStale()
        await scheduleNotifications()
        activityManager.checkAuthorization()
        activityManager.rehydrate()
    }
}

#Preview {
    TodayView()
}

// Long-list preview: two pinned teams + 13 other games, enough rows to scroll
// past both section headers and verify they scroll off rather than floating.
// Depends on ScheduleStore(previewGames:) and TodayView(previewStore:), both
// #if DEBUG-only — the whole block must be gated the same way, or it fails to
// compile in Release (previews aren't automatically excluded from compilation).
#if DEBUG
// NOTE: UserPreferences.shared persists to the real UserDefaults.standard —
// running this preview in Xcode overwrites your actual pinned teams on device.
//
// Factored out of the #Preview closure below: under this toolchain, a
// Void-typed assignment statement (UserPreferences.shared.pinnedTeams
// = ...) inside a #Preview macro's trailing closure defeats the
// macro's closure-return-type inference and fails the whole expansion with
// "type of expression is ambiguous without a type annotation" — moving the
// mutation into an ordinary function called from the closure sidesteps it.
private func longListPreviewStore() -> ScheduleStore {
    let games: [NHLGame] = [
        // Pinned
        NHLGame(id: 1, startTimeUTC: "2026-08-04T22:00:00Z", homeTeam: .init(abbrev: "BOS"), awayTeam: .init(abbrev: "NYR"), gameState: "FUT", gameType: 2),
        NHLGame(id: 2, startTimeUTC: "2026-08-05T00:00:00Z", homeTeam: .init(abbrev: "VAN"), awayTeam: .init(abbrev: "EDM"), gameState: "FUT", gameType: 2),
        // Other games
        NHLGame(id: 3,  startTimeUTC: "2026-08-04T22:00:00Z", homeTeam: .init(abbrev: "TOR"), awayTeam: .init(abbrev: "MTL"), gameState: "FUT", gameType: 2),
        NHLGame(id: 4,  startTimeUTC: "2026-08-04T22:00:00Z", homeTeam: .init(abbrev: "DET"), awayTeam: .init(abbrev: "CHI"), gameState: "FUT", gameType: 2),
        NHLGame(id: 5,  startTimeUTC: "2026-08-04T22:00:00Z", homeTeam: .init(abbrev: "PIT"), awayTeam: .init(abbrev: "WSH"), gameState: "FUT", gameType: 2),
        NHLGame(id: 6,  startTimeUTC: "2026-08-04T23:00:00Z", homeTeam: .init(abbrev: "NYI"), awayTeam: .init(abbrev: "NJD"), gameState: "FUT", gameType: 2),
        NHLGame(id: 7,  startTimeUTC: "2026-08-04T23:00:00Z", homeTeam: .init(abbrev: "CAR"), awayTeam: .init(abbrev: "FLA"), gameState: "FUT", gameType: 2),
        NHLGame(id: 8,  startTimeUTC: "2026-08-04T23:00:00Z", homeTeam: .init(abbrev: "CBJ"), awayTeam: .init(abbrev: "BUF"), gameState: "FUT", gameType: 2),
        NHLGame(id: 9,  startTimeUTC: "2026-08-05T00:00:00Z", homeTeam: .init(abbrev: "STL"), awayTeam: .init(abbrev: "MIN"), gameState: "FUT", gameType: 2),
        NHLGame(id: 10, startTimeUTC: "2026-08-05T00:00:00Z", homeTeam: .init(abbrev: "NSH"), awayTeam: .init(abbrev: "WPG"), gameState: "FUT", gameType: 2),
        NHLGame(id: 11, startTimeUTC: "2026-08-05T00:00:00Z", homeTeam: .init(abbrev: "DAL"), awayTeam: .init(abbrev: "COL"), gameState: "FUT", gameType: 2),
        NHLGame(id: 12, startTimeUTC: "2026-08-05T01:00:00Z", homeTeam: .init(abbrev: "CGY"), awayTeam: .init(abbrev: "SEA"), gameState: "FUT", gameType: 2),
        NHLGame(id: 13, startTimeUTC: "2026-08-05T01:00:00Z", homeTeam: .init(abbrev: "VGK"), awayTeam: .init(abbrev: "ANA"), gameState: "FUT", gameType: 2),
        NHLGame(id: 14, startTimeUTC: "2026-08-05T01:00:00Z", homeTeam: .init(abbrev: "LAK"), awayTeam: .init(abbrev: "SJS"), gameState: "FUT", gameType: 2),
        NHLGame(id: 15, startTimeUTC: "2026-08-05T01:30:00Z", homeTeam: .init(abbrev: "ARI"), awayTeam: .init(abbrev: "PHI"), gameState: "FUT", gameType: 2),
    ]
    UserPreferences.shared.pinnedTeams = ["BOS", "EDM"]
    return ScheduleStore(previewGames: games)
}

#Preview("Long list — scroll header test") {
    TodayView(previewStore: longListPreviewStore())
}
#endif
