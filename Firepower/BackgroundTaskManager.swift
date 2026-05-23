import BackgroundTasks
import Foundation

struct BackgroundTaskManager {

    static let refreshTaskID = "com.blakenelson.Firepower.scheduleRefresh"

    // MARK: - Registration (call from App.init)

    static func registerHandlers() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleRefresh(task: refreshTask)
        }
    }

    // MARK: - Scheduling

    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        // Earliest next morning at 6 AM
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        request.earliestBeginDate = Calendar.current.date(
            bySettingHour: 6, minute: 0, second: 0, of: tomorrow
        )
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handler

    private static func handleRefresh(task: BGAppRefreshTask) {
        scheduleNextRefresh() // re-arm immediately

        let handle = Task {
            do {
                let games = try await NHLScheduleClient.fetchTodayGames()

                // Persist to cache (same keys ScheduleStore reads on next launch)
                if let data = try? JSONEncoder().encode(games) {
                    UserDefaults.standard.set(data, forKey: "cachedGames")
                }
                if let dateData = try? JSONEncoder().encode(Date()) {
                    UserDefaults.standard.set(dateData, forKey: "cachedGamesDate")
                }

                let prefs = UserPreferences.shared
                await NotificationManager.scheduleDailySummary(games: games, prefs: prefs)
                await NotificationManager.schedulePregameAlerts(games: games, prefs: prefs)

                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            handle.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
