import FirepowerShared
import SwiftUI

// TeamPickerView — shown on first launch when no team is selected,
// and reachable via "Change Team" from ContentView.
//
// Persists the selected tricode to @AppStorage("trackedTeamTricode").
// On selection the view dismisses itself; the root view reacts to the
// AppStorage change and switches to ContentView.

struct TeamPickerView: View {

    @AppStorage("trackedTeamTricode") private var trackedTeamTricode: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(NHLTeam.all) { team in
                Button {
                    trackedTeamTricode = team.tricode
                    dismiss()
                } label: {
                    TeamRow(team: team)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Choose Your Team")
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.plain)
        }
    }
}

// MARK: - Row

private struct TeamRow: View {
    let team: NHLTeam

    var body: some View {
        HStack(spacing: 14) {
            // Color swatch
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: team.primaryColor))
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(team.tricode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview("Picker") {
    TeamPickerView()
}
