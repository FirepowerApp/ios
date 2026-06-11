#if DEBUG
import ActivityKit
import FirepowerShared
import SwiftUI

// Debug-only Live Activity controls.
// Shown at the bottom of TodayView in DEBUG builds.
// Lets you start a fake BOS@NYR game and drive state changes locally
// via Activity.update() without any APNs pushes.

struct DebugLiveActivityControls: View {
    @ObservedObject var activityManager: LiveActivityManager

    // Mutable fake state — modified by the control buttons.
    @State private var homeScore = 2
    @State private var awayScore = 1
    @State private var homeXG   = 2.4
    @State private var awayXG   = 1.8
    @State private var period   = 2
    @State private var minutes  = 14
    @State private var seconds  = 32

    private var isTracking: Bool { activityManager.state == .tracking }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Score readout
            HStack {
                Text("BOS \(homeScore) – \(awayScore) NYR")
                    .font(.headline.monospacedDigit())
                Spacer()
                Text(clockString)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Start / stop row
            HStack(spacing: 10) {
                Button(isTracking ? "Stop" : "Start Debug Activity") {
                    Task {
                        if isTracking {
                            await activityManager.stopActivity()
                        } else {
                            resetState()
                            await activityManager.startDebugActivity(
                                initialState: currentContentState(eventType: nil, eventDetail: nil, eventTeam: nil)
                            )
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(isTracking ? .red : .blue)
            }

            if isTracking {
                // Score buttons
                HStack(spacing: 8) {
                    Button("BOS Goal") {
                        homeScore += 1
                        homeXG   += Double.random(in: 0.2...0.6)
                        push(eventType: "goal", eventDetail: "Marchand", eventTeam: "BOS")
                    }
                    .buttonStyle(.bordered)

                    Button("NYR Goal") {
                        awayScore += 1
                        awayXG   += Double.random(in: 0.2...0.6)
                        push(eventType: "goal", eventDetail: "Zibanejad", eventTeam: "NYR")
                    }
                    .buttonStyle(.bordered)

                    Button("Penalty") {
                        push(eventType: "penalty", eventDetail: "Tripping 2:00", eventTeam: "NYR")
                    }
                    .buttonStyle(.bordered)
                }

                // Period / time controls
                HStack(spacing: 8) {
                    Button("−1 min") {
                        advanceClock(by: 60)
                        push(eventType: nil, eventDetail: nil, eventTeam: nil)
                    }
                    .buttonStyle(.bordered)

                    Button("Next Period") {
                        if period < 3 {
                            period  += 1
                            minutes  = 20
                            seconds  = 0
                        } else {
                            // OT
                            period  = 4
                            minutes = 5
                            seconds = 0
                        }
                        push(eventType: nil, eventDetail: nil, eventTeam: nil)
                    }
                    .buttonStyle(.bordered)

                    Button("Final") {
                        Task {
                            await activityManager.updateDebugState(
                                .init(homeScore: homeScore, awayScore: awayScore,
                                      homeXG: homeXG, awayXG: awayXG,
                                      gameState: "Final")
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var clockString: String {
        String(format: "%d:%02d left, %@", minutes, seconds, periodLabel)
    }

    private var periodLabel: String {
        switch period {
        case 1: return "1st period"
        case 2: return "2nd period"
        case 3: return "3rd period"
        default: return "OT"
        }
    }

    private func currentContentState(eventType: String?, eventDetail: String?, eventTeam: String?) -> FirepowerActivityAttributes.ContentState {
        .init(homeScore: homeScore, awayScore: awayScore,
              homeXG: round(homeXG * 100) / 100,
              awayXG: round(awayXG * 100) / 100,
              gameState: clockString,
              eventType: eventType, eventDetail: eventDetail, eventTeam: eventTeam)
    }

    private func push(eventType: String?, eventDetail: String?, eventTeam: String?) {
        Task {
            await activityManager.updateDebugState(
                currentContentState(eventType: eventType, eventDetail: eventDetail, eventTeam: eventTeam)
            )
        }
    }

    private func advanceClock(by totalSeconds: Int) {
        let total = minutes * 60 + seconds - totalSeconds
        if total <= 0 { minutes = 0; seconds = 0 }
        else { minutes = total / 60; seconds = total % 60 }
    }

    private func resetState() {
        homeScore = 2; awayScore = 1
        homeXG    = 2.4; awayXG  = 1.8
        period    = 2;  minutes  = 14; seconds = 32
    }
}

#Preview {
    let mgr = LiveActivityManager()
    return DebugLiveActivityControls(activityManager: mgr)
        .padding()
}
#endif
