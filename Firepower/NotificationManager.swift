import UserNotifications
import Foundation

struct NotificationManager {

    // MARK: - Permission

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    // MARK: - Daily morning summary

    /// Call after each schedule fetch. Schedules a 10 AM summary for today.
    static func scheduleDailySummary(games: [NHLGame], prefs: UserPreferences) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["firepower-daily-summary"])

        guard prefs.notificationsEnabled, prefs.notificationFrequency != .off else { return }

        let pinnedGames = games.filter { $0.pinnedTricode(from: prefs.pinnedTeams) != nil }

        if prefs.notificationFrequency == .pinnedOnly, pinnedGames.isEmpty { return }
        guard !games.isEmpty else { return }

        let relevant = prefs.notificationFrequency == .pinnedOnly ? pinnedGames : games
        let lines = relevant.prefix(3).map { "\($0.awayTeam.abbrev) @ \($0.homeTeam.abbrev) · \($0.formattedStartTime)" }
        let body = lines.joined(separator: "\n")

        let content = UNMutableNotificationContent()
        content.title = "Hockey tonight"
        content.body = body.isEmpty
            ? "\(games.count) game\(games.count == 1 ? "" : "s") on the schedule"
            : body
        content.sound = .default

        var dc = DateComponents()
        dc.hour = 10
        dc.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        let request = UNNotificationRequest(identifier: "firepower-daily-summary", content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Pre-game notifications for pinned teams

    /// Schedule a "starts in 15 min" notification for each pinned team's upcoming game.
    /// Tapping opens the app; the app uses the userInfo to auto-start the Live Activity.
    static func schedulePregameAlerts(games: [NHLGame], prefs: UserPreferences) async {
        let center = UNUserNotificationCenter.current()

        // Remove any existing pre-game alerts
        let pending = await center.pendingNotificationRequests()
        let pregameIDs = pending.filter { $0.identifier.hasPrefix("firepower-pregame-") }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: pregameIDs)

        guard prefs.notificationsEnabled else { return }

        let now = Date()
        for game in games {
            guard let start = game.startDate, start > now else { continue }
            guard let tricode = game.pinnedTricode(from: prefs.pinnedTeams) else { continue }

            let alertTime = start.addingTimeInterval(-10 * 60) // 10 min before
            guard alertTime > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(game.awayTeam.abbrev) @ \(game.homeTeam.abbrev) starts soon"
            content.body = "Tap to track the game on your lock screen"
            content.sound = .default
            content.userInfo = [
                "gameID":       String(game.id),
                "homeTeam":     game.homeTeam.abbrev,
                "awayTeam":     game.awayTeam.abbrev,
                "tricode":      tricode,
                "startTimeUTC": game.startTimeUTC
            ]

            let dc = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: alertTime)
            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
            let request = UNNotificationRequest(
                identifier: "firepower-pregame-\(game.id)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
