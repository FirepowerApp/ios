import SwiftUI
import UserNotifications

@main
struct FirepowerApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        BackgroundTaskManager.registerHandlers()
        BackgroundTaskManager.scheduleNextRefresh()
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
        }
    }
}

// MARK: - App delegate (notification deep-link routing)

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Foreground notification display
    // Suppress pre-game banners when the user is already in the app viewing the game list.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier.hasPrefix("firepower-pregame-") {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    // Tap handling — pre-game alerts carry game info in userInfo;
    // we open a deep link so TodayView can auto-start the activity.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let gameID   = info["gameID"]   as? String,
           let homeTeam = info["homeTeam"] as? String,
           let awayTeam = info["awayTeam"] as? String {
            var components = URLComponents()
            components.scheme = "firepower"
            components.host = "start"
            components.queryItems = [
                URLQueryItem(name: "gameID",   value: gameID),
                URLQueryItem(name: "homeTeam", value: homeTeam),
                URLQueryItem(name: "awayTeam", value: awayTeam),
            ]
            if let url = components.url {
                UIApplication.shared.open(url)
            }
        }
        completionHandler()
    }
}
