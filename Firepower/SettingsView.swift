import FirepowerShared
import SwiftUI
import UserNotifications

struct SettingsView: View {

    @ObservedObject private var prefs = UserPreferences.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingPermissionAlert = false
    @State private var notificationPermissionDenied = false

    var body: some View {
        NavigationStack {
            Form {
                pinnedTeamsSection
                notificationsSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await checkNotificationPermission() }
    }

    // MARK: - Pinned Teams

    private var pinnedTeamsSection: some View {
        Section {
            teamRowList()
        } header: {
            Text("Pinned Teams")
        } footer: {
            Text("Pinned teams appear at the top of Tonight's games list and get a 10-minute heads-up before puck drop.")
        }
    }

    // Workaround: SwiftUI type inference fails when ForEach<[NHLTeam]> is inlined directly into Section
    @ViewBuilder
    private func teamRowList() -> some View {
        let teams: [NHLTeam] = NHLTeam.all
        ForEach(teams, id: \.tricode) { (team: NHLTeam) in
            teamRow(team)
        }
    }

    private func teamRow(_ team: NHLTeam) -> some View {
        Button {
            prefs.togglePin(team.tricode)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: team.primaryColor))
                    .frame(width: 12, height: 12)

                Text(team.name)
                    .foregroundStyle(.primary)

                Spacer()

                Text(team.tricode)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if prefs.pinnedTeams.contains(team.tricode) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle("Send Reminders", isOn: $prefs.notificationsEnabled)
                .onChange(of: prefs.notificationsEnabled) { _, enabled in
                    if enabled {
                        Task { await requestPermissionIfNeeded() }
                    }
                }

            if prefs.notificationsEnabled {
                if notificationPermissionDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Notifications blocked — open Settings", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                } else {
                    Picker("Remind me", selection: $prefs.notificationFrequency) {
                        ForEach(NotificationFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        } header: {
            Text("Daily Reminder")
        } footer: {
            if prefs.notificationsEnabled && !notificationPermissionDenied {
                Text("A morning summary appears at 10 AM. Pinned teams also get a 10-minute heads-up before puck drop.")
            }
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            if let lastAutoStart = UserDefaults.standard.string(forKey: "lastAutoStartLog") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last pre-game alert")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lastAutoStart)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let lastFetch = UserDefaults.standard.data(forKey: "cachedGamesDate"),
               let date = try? JSONDecoder().decode(Date.self, from: lastFetch) {
                LabeledContent("Last schedule fetch") {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    #endif

    // MARK: - Permission helpers

    private func checkNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationPermissionDenied = settings.authorizationStatus == .denied
    }

    private func requestPermissionIfNeeded() async {
        let granted = await NotificationManager.requestPermission()
        notificationPermissionDenied = !granted
    }
}
