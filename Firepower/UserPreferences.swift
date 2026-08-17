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

    private let defaults: UserDefaults

    /// Not cached. Reading before the first unlock after a reboot (e.g. a
    /// system background launch) can transiently see an empty store; caching
    /// that read and then persisting the whole set on the next mutation is how
    /// pinned teams used to get wiped. Reading straight through `defaults` every
    /// time means a stale/empty in-memory snapshot can never clobber disk — the
    /// setter is always a read-modify-write against the live store.
    var pinnedTeams: Set<String> {
        get { Set(Self.read([String].self, key: "pinnedTeams", from: defaults) ?? []) }
        set {
            objectWillChange.send()
            persist([String](newValue), key: "pinnedTeams")
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet { persist(notificationsEnabled, key: "notificationsEnabled") }
    }

    @Published var notificationFrequency: NotificationFrequency {
        didSet { persist(notificationFrequency.rawValue, key: "notificationFrequency") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notificationsEnabled = Self.read(Bool.self, key: "notificationsEnabled", from: defaults) ?? true
        notificationFrequency = NotificationFrequency(
            rawValue: Self.read(String.self, key: "notificationFrequency", from: defaults) ?? ""
        ) ?? .always
    }

    func togglePin(_ tricode: String) {
        var current = pinnedTeams          // fresh read from the live store
        if current.contains(tricode) {
            current.remove(tricode)
        } else {
            current.insert(tricode)
        }
        pinnedTeams = current              // fires objectWillChange + persists the merged set
    }

    // MARK: - Persistence

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
