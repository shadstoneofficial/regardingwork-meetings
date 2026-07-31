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
                failure: "write failed"
            ),
            sessionStartedAt: start,
            now: now
        )
        #expect(failed.state == .failed)
    }
}
