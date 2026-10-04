import Foundation
import Testing
@testable import RegardingWorkMeetings

@Suite("Recording health")
struct RecordingHealthTests {
    @Test("silent buffers are never reported active")
    func silentIsVisible() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = start.addingTimeInterval(20)
        let health = TrackHealthEvaluator.evaluate(
            snapshot: RecorderSnapshot(
                isRecording: true,
                firstBufferAt: start,
                lastBufferAt: now,
                lastSignalAt: nil,
                lastNonzeroAt: now,
                failure: nil
            ),
            sessionStartedAt: start,
            now: now
        )
        #expect(health.state == .silent)
        #expect(health.needsAttention)
    }

    @Test("stalled and failed tracks are visible")
    func stalledAndFailed() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = start.addingTimeInterval(30)
        let stalled = TrackHealthEvaluator.evaluate(
            snapshot: RecorderSnapshot(
                isRecording: true,
                firstBufferAt: start,
                lastBufferAt: start,
                lastSignalAt: start,
                lastNonzeroAt: start,
                failure: nil
            ),
            sessionStartedAt: start,
            now: now
        )
        #expect(stalled.state == .stalled)

        let failed = TrackHealthEvaluator.evaluate(
            snapshot: RecorderSnapshot(
                isRecording: true,
                firstBufferAt: nil,
                lastBufferAt: nil,
                lastSignalAt: nil,
                lastNonzeroAt: nil,
                failure: "write failed"
            ),
            sessionStartedAt: start,
            now: now
        )
        #expect(failed.state == .failed)
    }

    @Test("zero-filled microphone buffers are distinguished from ordinary quiet")
    func digitalSilenceIsCritical() {
        let start = Date(timeIntervalSince1970: 1_000)
        let now = start.addingTimeInterval(20)
        let health = TrackHealthEvaluator.evaluate(
            snapshot: RecorderSnapshot(
                isRecording: true,
                firstBufferAt: start,
                lastBufferAt: now,
                lastSignalAt: nil,
                lastNonzeroAt: nil,
                zeroFilledSince: start,
                failure: nil
            ),
            sessionStartedAt: start,
            now: now,
            detectDigitalSilence: true
        )
        #expect(health.state == .digitalSilence)
        #expect(health.needsAttention)
    }

    @Test("digital-silence recovery is delayed and attempted only once")
    func recoveryPolicy() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(
            !MicrophoneSafety.shouldScheduleRecovery(
                zeroFilledSince: start,
                now: start.addingTimeInterval(1),
                recoveryAttempted: false,
                recoveryScheduled: false
            )
        )
        #expect(
            MicrophoneSafety.shouldScheduleRecovery(
                zeroFilledSince: start,
                now: start.addingTimeInterval(2),
                recoveryAttempted: false,
                recoveryScheduled: false
            )
        )
        #expect(
            !MicrophoneSafety.shouldScheduleRecovery(
                zeroFilledSince: start,
                now: start.addingTimeInterval(20),
                recoveryAttempted: true,
                recoveryScheduled: false
            )
        )
    }

    @Test("default microphone route changes are explicit")
    func routeChange() {
        let healthy = TrackHealth(state: .active, detail: "signal detected")
        let builtIn = AudioInputDeviceIdentity(id: 1, uid: "built-in", name: "MacBook Microphone")
        let headset = AudioInputDeviceIdentity(id: 2, uid: "headset", name: "USB Headset")
        #expect(
            MicrophoneSafety.applyingRouteChange(
                to: healthy,
                startedDevice: builtIn,
                currentDevice: builtIn
            ) == healthy
        )
        let changed = MicrophoneSafety.applyingRouteChange(
            to: healthy,
            startedDevice: builtIn,
            currentDevice: headset
        )
        #expect(changed.state == .routeChanged)
        #expect(changed.needsAttention)
        #expect(changed.detail.contains("MacBook Microphone"))
        #expect(changed.detail.contains("USB Headset"))
        #expect(MicrophoneSafety.menuBarLabel(for: .starting) == " CHECK MIC")
        #expect(MicrophoneSafety.menuBarLabel(for: .silent) == " CHECK MIC")
        #expect(MicrophoneSafety.menuBarLabel(for: .digitalSilence) == " MIC!")
        #expect(MicrophoneSafety.menuBarLabel(for: .active).isEmpty)
    }
}
