import SwiftUI
import ActivityKit

// ContentView — the single app screen.
//
// States:
//   idle (game tonight)   → team logo + matchup + "Start Tracking" button
//   idle (no game)        → team logo + "BOS doesn't play tonight. Next: ..." + disabled button
//   permission denied     → "Turn on Live Activities" + Settings deep-link
//   starting (~1s)        → button disabled, "Starting..."
//   tracking              → "Tracking BOS vs NYR · you can close this app"
//
// Visual: full-bleed team primary color background, composition-first layout.
// v1: BOS hardcoded. Team picker is TODO #1 (Approach B).

struct ContentView: View {

    // MARK: - v1 hardcoded team config
    private let trackedTeam = TeamConfig.boston

    @StateObject private var activityManager = LiveActivityManager()
    @State private var nextGame: NextGame? = nil
    @State private var isLoadingGame = false

    var body: some View {
        ZStack {
            Color(hex: trackedTeam.primaryColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Team logo
                Image(trackedTeam.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .padding(.bottom, 24)

                // Game info
                gameInfoView

                Spacer()

                // Action button
                actionButton
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
            }
        }
        .task { await loadNextGame() }
        .onAppear { activityManager.checkAuthorization() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var gameInfoView: some View {
        switch activityManager.state {
        case .denied:
            Text("Live Activities are off")
                .font(.headline)
                .foregroundStyle(Color(hex: trackedTeam.secondaryColor))
        case .tracking:
            if let game = nextGame {
                Text("Tracking \(trackedTeam.tricode) vs \(game.opponentTricode)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(hex: trackedTeam.secondaryColor))
                Text("You can close this app")
                    .font(.caption)
                    .foregroundStyle(Color(hex: trackedTeam.secondaryColor).opacity(0.7))
                    .padding(.top, 4)
            }
        default:
            if let game = nextGame {
                Text("\(trackedTeam.tricode) vs \(game.opponentTricode)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(hex: trackedTeam.secondaryColor))
                Text(game.formattedTime)
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: trackedTeam.secondaryColor).opacity(0.8))
                    .padding(.top, 4)
            } else if !isLoadingGame {
                Text("\(trackedTeam.name) doesn't play tonight")
                    .font(.headline)
                    .foregroundStyle(Color(hex: trackedTeam.secondaryColor))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch activityManager.state {
        case .denied:
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(FirepowerButtonStyle(
                background: Color(hex: trackedTeam.secondaryColor),
                foreground: Color(hex: trackedTeam.primaryColor)
            ))

        case .starting:
            Button("Starting...") {}
                .buttonStyle(FirepowerButtonStyle(
                    background: Color(hex: trackedTeam.secondaryColor).opacity(0.5),
                    foreground: Color(hex: trackedTeam.primaryColor)
                ))
                .disabled(true)

        case .tracking:
            Button("Stop Tracking") {
                Task { await activityManager.stopActivity() }
            }
            .buttonStyle(FirepowerButtonStyle(
                background: Color(hex: trackedTeam.secondaryColor).opacity(0.6),
                foreground: Color(hex: trackedTeam.primaryColor)
            ))

        default:
            let hasGame = nextGame != nil
            Button("Start Tracking") {
                guard let game = nextGame else { return }
                Task {
                    await activityManager.startActivity(
                        homeTeam: trackedTeam.tricode,
                        awayTeam: game.opponentTricode,
                        gameID: game.gameID
                    )
                }
            }
            .buttonStyle(FirepowerButtonStyle(
                background: Color(hex: trackedTeam.secondaryColor),
                foreground: Color(hex: trackedTeam.primaryColor)
            ))
            .disabled(!hasGame)
            .opacity(hasGame ? 1 : 0.5)
        }
    }

    // MARK: - Data loading

    private func loadNextGame() async {
        isLoadingGame = true
        defer { isLoadingGame = false }
        // TODO: call GET /api/v1/teams/{tricode}/next-game
        // For v1 development, stub with a fake game:
        nextGame = NextGame(
            gameID: "2025020001",
            opponentTricode: "NYR",
            formattedTime: "Tonight · 7:00 PM"
        )
    }
}

// MARK: - Models

struct TeamConfig {
    let tricode: String
    let name: String
    let logoAssetName: String
    let primaryColor: String   // hex
    let secondaryColor: String // hex

    static let boston = TeamConfig(
        tricode: "BOS",
        name: "Boston Bruins",
        logoAssetName: "bos",
        primaryColor: "#FFB81C",
        secondaryColor: "#000000"
    )
}

struct NextGame {
    let gameID: String
    let opponentTricode: String
    let formattedTime: String
}

// MARK: - Button style

struct FirepowerButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let v = UInt64(h, radix: 16) ?? 0
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
