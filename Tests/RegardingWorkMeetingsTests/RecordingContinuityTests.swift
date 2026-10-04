import AppKit
import CoreFoundation
import Foundation
import Testing
@testable import RegardingWorkMeetings

@Suite("Recording monitor and continuity")
struct RecordingContinuityTests {
    @Test("repeated failed restarts pad only newly elapsed time, including partially committed chunks")
    func paddingDoesNotRepeat() {
        let start = Date(timeIntervalSince1970: 1_000)
        var timeline = CaptureGapTimeline()
        timeline.noteBuffer(at: start)
        #expect(timeline.missingSeconds(until: start.addingTimeInterval(3)) == 3)
        timeline.commitPadding(seconds: 3)
        #expect(timeline.missingSeconds(until: start.addingTimeInterval(5)) == 2)
        timeline.commitPadding(seconds: 1)
        #expect(timeline.missingSeconds(until: start.addingTimeInterval(5)) == 1)
        timeline.commitPadding(seconds: 1)
        #expect(timeline.missingSeconds(until: start.addingTimeInterval(5)) == 0)
        timeline.noteBuffer(at: start.addingTimeInterval(6))
        #expect(timeline.missingSeconds(until: start.addingTimeInterval(7)) == 1)
    }

    @Test("stop invalidates pending retries, including after another capture starts")
    func stoppedRetriesStayStopped() {
        var generation = CaptureRestartGeneration()
        generation.start()
        let first = generation.value
        #expect(generation.permits(first))
        generation.stop()
        #expect(!generation.permits(first))
        generation.start()
        #expect(!generation.permits(first))
        #expect(generation.permits(generation.value))
    }

    @Test("route history retains observed changes without duplicating stable polls")
    func routesRemainHistorical() {
        var history = MicrophoneRouteHistory()
        let one = AudioInputDeviceIdentity(id: 1, uid: "fixture-one", name: "First mic")
        let two = AudioInputDeviceIdentity(id: 2, uid: "fixture-two", name: "Current mic")
        let date = Date(timeIntervalSince1970: 1_000)
        history.observe(one, at: date)
        history.observe(one, at: date.addingTimeInterval(1))
        history.observe(two, at: date.addingTimeInterval(2))
        history.observe(nil, at: date.addingTimeInterval(3))
        #expect(history.observations.map(\.device) == [one, two, nil])
        let failure = TrackHealth(state: .digitalSilence, detail: "digital zeros")
        let changed = MicrophoneSafety.applyingRouteChange(to: failure, startedDevice: one, currentDevice: two)
        #expect(changed.state == .digitalSilence)
        #expect(changed.detail.contains("Current mic"))
        #expect(MicrophoneSafety.applyingRouteChange(to: failure, startedDevice: one, currentDevice: nil).state == .digitalSilence)
    }

    @Test("the common-mode monitor fires during synthetic menu-tracking mode")
    @MainActor
    func trackingModeTimer() {
        var ticks = 0
        // A CLI test runner lacks AppKit's automatic menu-mode registration.
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: RunLoop.Mode.eventTracking.rawValue as CFString))
        let timer = RecordingMonitor.schedule(interval: 0.01) { ticks += 1 }
        defer { timer.invalidate() }
        let until = Date().addingTimeInterval(0.1)
        while Date() < until {
            _ = RunLoop.main.run(mode: .eventTracking, before: until)
        }
        #expect(ticks > 0)
    }
}
