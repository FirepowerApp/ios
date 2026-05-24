import Foundation
import Combine

enum NotificationFrequency: String, CaseIterable, Codable {
    case always     = "always"
    case pinnedOnly = "pinnedOnly"
    case off        = "off"

    var displayName: String {
        switch self {
        case .always:     return "Every day with games"
        case .pinnedOnly: return "Only when pinned teams play"
        case .off:        return "Never"
        }
    }
}

final class UserPreferences: ObservableObject {

    static let shared = UserPreferences()

    @Published var pinnedTeams: Set<String> {
        didSet { persist([String](pinnedTeams), key: "pinnedTeams") }
    }

    @Published var notificationsEnabled: Bool {
        didSet { persist(notificationsEnabled, key: "notificationsEnabled") }
    }

    @Published var notificationFrequency: NotificationFrequency {
        didSet { persist(notificationFrequency.rawValue, key: "notificationFrequency") }
    }

    private init() {
        pinnedTeams          = Set(Self.read([String].self, key: "pinnedTeams") ?? [])
        notificationsEnabled = Self.read(Bool.self, key: "notificationsEnabled") ?? true
        notificationFrequency = NotificationFrequency(
            rawValue: Self.read(String.self, key: "notificationFrequency") ?? ""
        ) ?? .always
    }

    func togglePin(_ tricode: String) {
        if pinnedTeams.contains(tricode) {
            pinnedTeams.remove(tricode)
        } else {
            pinnedTeams.insert(tricode)
        }
    }

    // MARK: - Persistence

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
