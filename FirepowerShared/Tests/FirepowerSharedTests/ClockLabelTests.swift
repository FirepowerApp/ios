import Foundation
import Testing
@testable import FirepowerShared

// MARK: - ContentState.clockLabel

// The pregame progression: scheduled start time until puck drop, then
// "Pregame" until the first push, then the pushed gameState, then "Final".
@Suite("ContentState.clockLabel")
struct ClockLabelTests {

    private let pregame = FirepowerActivityAttributes.ContentState()  // gameState: ""
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    @Test("pregame before puck drop shows the scheduled local time")
    func scheduledTime() {
        let start = now.addingTimeInterval(8 * 3600)
        let label = pregame.clockLabel(startTime: start, isStale: false, now: now)
        #expect(label == start.formatted(date: .omitted, time: .shortened))
        #expect(label != "Pregame")
    }

    @Test("pregame flips to Pregame once the start time passes")
    func startTimePassed() {
        let start = now.addingTimeInterval(-60)
        #expect(pregame.clockLabel(startTime: start, isStale: false, now: now) == "Pregame")
    }

    @Test("pregame flips to Pregame on the stale re-render at puck drop")
    func staleAtPuckDrop() {
        // At the stale-date the wall clock equals startTime; isStale alone must flip it.
        let start = now.addingTimeInterval(3600)
        #expect(pregame.clockLabel(startTime: start, isStale: true, now: now) == "Pregame")
    }

    @Test("pregame with no start time shows Pregame")
    func noStartTime() {
        #expect(pregame.clockLabel(startTime: nil, isStale: false, now: now) == "Pregame")
    }

    @Test("first push replaces pregame with the game clock")
    func liveGameState() {
        let live = FirepowerActivityAttributes.ContentState.preview  // "14:32 left, 2nd period"
        let start = now.addingTimeInterval(3600)
        #expect(live.clockLabel(startTime: start, isStale: false, now: now) == "14:32 left, 2nd period")
    }

    @Test("ended game shows Final regardless of start time")
    func ended() {
        let final = FirepowerActivityAttributes.ContentState.previewEnded
        let start = now.addingTimeInterval(3600)
        #expect(final.clockLabel(startTime: start, isStale: false, now: now) == "Final")
    }
}
