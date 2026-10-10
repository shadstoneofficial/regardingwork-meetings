import AVFoundation
import Foundation
import Testing
@testable import RegardingWorkMeetings

private final class FixtureSystemRecorder: SystemAudioRecording {
    enum Failure: Error { case synthetic }
    var ownsOutputFile = false
    var failStart = false
    var retryableStartFailure = true
    var stopped = false
    var value = RecorderSnapshot(isRecording: true, firstBufferAt: nil, lastBufferAt: nil,
        lastSignalAt: nil, lastNonzeroAt: nil, failure: nil)

    func start(writingToNewFile url: URL, beforeCapture: () throws -> Void) throws {
        try SecureStorage.reserveNewFile(url)
        ownsOutputFile = true
        try beforeCapture()
        if failStart { value.retryableFailure = retryableStartFailure; throw Failure.synthetic }
    }
    func stop() { stopped = true; value.isRecording = false }
    func snapshot() -> RecorderSnapshot { value }
    func buffer(_ date: Date, signal: Bool = true) {
        if value.firstBufferAt == nil { value.firstBufferAt = date }
        value.lastBufferAt = date
        if signal { value.lastSignalAt = date }
        value.framesWritten += 480
        value.sampleRate = 48_000
    }
}

@Suite("Bounded, data-preserving system capture recovery")
struct SystemCaptureRecoveryTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rwm-system-\(UUID())")
        try SecureStorage.createDirectory(url)
        return url
    }

    @Test("a 15-minute stall preserves original audio and a resumed segment's real offset")
    func longSessionStall() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = FixtureSystemRecorder(), resumed = FixtureSystemRecorder()
        var starts = 0
        let controller = SystemCaptureController(directory: root, startedAt: start) {
            starts += 1
            return starts == 1 ? first : resumed
        }
        var persistedNames: [[String]] = []
        controller.beforeCapture = { persistedNames.append(controller.segments(origin: start).map(\.file)) }
        try controller.start(now: start)
        let original = root.appendingPathComponent("system.caf")
        let sentinel = Data("synthetic original audio evidence".utf8)
        try SecureStorage.write(sentinel, to: original)
        first.buffer(start)
        first.buffer(start.addingTimeInterval(900))
        #expect(controller.health(now: start.addingTimeInterval(900), uptime: 900).state == .active)
        #expect(controller.health(now: start.addingTimeInterval(916), uptime: 916).state == .stalled)
        #expect(first.stopped)
        #expect(controller.health(now: start.addingTimeInterval(917), uptime: 917).state == .recovering)
        #expect(starts == 1)
        #expect(controller.health(now: start.addingTimeInterval(918), uptime: 918).state == .recovering)
        #expect(starts == 2)
        #expect(controller.health(now: start.addingTimeInterval(919), uptime: 919).state == .recovering)
        resumed.buffer(start.addingTimeInterval(920))
        #expect(controller.health(now: start.addingTimeInterval(920), uptime: 920).state == .recovered)
        controller.stop()
        let segments = controller.segments(origin: start)
        #expect(segments.map(\.file) == ["system.caf", "system.recovery-001.caf"])
        #expect(segments.map(\.offset_ms) == [0, 920_000])
        #expect(controller.interruptions.first?.resumed_at == ISO8601DateFormatter().string(from: start.addingTimeInterval(920)))
        #expect(try Data(contentsOf: original) == sentinel)
        #expect(persistedNames == [["system.caf"], ["system.caf", "system.recovery-001.caf"]])
        #expect(controller.recoveryAttempts == 1)
        #expect(controller.wasInterrupted)
    }

    @Test("ordinary quiet with fresh buffers never restarts the tap")
    func quietIsNotFailure() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = FixtureSystemRecorder()
        var starts = 0
        let controller = SystemCaptureController(directory: root, startedAt: start) { starts += 1; return recorder }
        try controller.start(now: start)
        for second in 0...120 {
            let now = start.addingTimeInterval(Double(second))
            recorder.buffer(now, signal: false)
            #expect(controller.health(now: now, uptime: Double(second)).state == .silent)
        }
        #expect(starts == 1)
        #expect(!controller.wasInterrupted)
        #expect(controller.recoveryAttempts == 0)
        controller.stop()
    }

    @Test("failed restarts are bounded; neither stop nor a final health read can restart capture")
    func boundedAndCancelled() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        var starts = 0
        let controller = SystemCaptureController(directory: root, startedAt: start) {
            starts += 1
            let recorder = FixtureSystemRecorder()
            recorder.failStart = starts > 1
            return recorder
        }
        try controller.start(now: start)
        for second in 6...60 {
            _ = controller.health(now: start.addingTimeInterval(Double(second)), uptime: Double(second))
        }
        #expect(starts == 4)
        #expect(controller.recoveryAttempts == 3)
        #expect(controller.health(now: start.addingTimeInterval(61), uptime: 61).detail.contains("exhausted"))
        #expect(controller.segments(origin: start).count == 4)
        controller.stop()
        _ = controller.health(now: start.addingTimeInterval(500), uptime: 500)
        #expect(starts == 4)

        var cancelledStarts = 0
        // A second directory avoids the original session's reserved file.
        let nextRoot = try folder()
        defer { try? FileManager.default.removeItem(at: nextRoot) }
        let next = SystemCaptureController(directory: nextRoot, startedAt: start) {
            cancelledStarts += 1; return FixtureSystemRecorder()
        }
        try next.start(now: start)
        _ = next.health(now: start.addingTimeInterval(6), uptime: 6)
        _ = next.health(now: start.addingTimeInterval(20), uptime: 20, allowRecovery: false)
        #expect(cancelledStarts == 1)
        next.stop()
        _ = next.health(now: start.addingTimeInterval(50), uptime: 50)
        #expect(cancelledStarts == 1)
    }

    @Test("storage write errors halt system capture without a restart loop")
    func storageFailure() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = FixtureSystemRecorder()
        var starts = 0
        let controller = SystemCaptureController(directory: root, startedAt: start) { starts += 1; return recorder }
        try controller.start(now: start)
        recorder.value.failure = "synthetic storage write failed"
        for second in 1...30 {
            #expect(controller.health(now: start.addingTimeInterval(Double(second)), uptime: Double(second)).state == .failed)
        }
        #expect(recorder.stopped)
        #expect(starts == 1)
        #expect(controller.recoveryAttempts == 0)
        controller.stop()
    }

    @Test("a storage or manifest startup failure stops recovery instead of retrying it")
    func recoveryStartupSafety() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        var starts = 0
        let controller = SystemCaptureController(directory: root, startedAt: start) {
            starts += 1
            let recorder = FixtureSystemRecorder()
            recorder.failStart = starts > 1
            recorder.retryableStartFailure = false
            return recorder
        }
        try controller.start(now: start)
        _ = controller.health(now: start.addingTimeInterval(6), uptime: 6)
        for second in 8...30 {
            #expect(controller.health(now: start.addingTimeInterval(Double(second)), uptime: Double(second)).state == .failed)
        }
        #expect(starts == 2)
        #expect(controller.recoveryAttempts == 1)
        #expect(controller.segments(origin: start).count == 2)
        controller.stop()
    }

    @Test("existing output and symlinks are refused without altering their contents")
    func exclusiveFiles() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("system.caf")
        let evidence = Data("preserve me".utf8)
        try SecureStorage.write(evidence, to: file)
        #expect(throws: (any Error).self) { try SecureStorage.reserveNewFile(file) }
        let link = root.appendingPathComponent("system.recovery-001.caf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: (any Error).self) { try SecureStorage.reserveNewFile(link) }
        #expect(try Data(contentsOf: file) == evidence)
        let controller = SystemCaptureController(directory: root, startedAt: start) { FixtureSystemRecorder() }
        #expect(throws: (any Error).self) { try controller.start(now: start) }
        #expect(controller.segments(origin: start).isEmpty)
        let newFile = root.appendingPathComponent("new.caf")
        try SecureStorage.reserveNewFile(newFile)
        #expect((try FileManager.default.attributesOfItem(atPath: newFile.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("failed manifest persistence prevents capture and preserves the reserved attempt")
    func manifestPrecondition() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = FixtureSystemRecorder()
        let controller = SystemCaptureController(directory: root, startedAt: start) { recorder }
        controller.beforeCapture = { throw FixtureSystemRecorder.Failure.synthetic }
        #expect(throws: (any Error).self) { try controller.start(now: start) }
        #expect(recorder.stopped)
        #expect(controller.segments(origin: start).first?.capture_started == false)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("system.caf").path))
    }

    @Test("system failures and prior gaps stay visible even with a healthy microphone")
    func warningLabelsAndVersion() {
        #expect(CaptureWarningLabel.text(mic: .active, system: .stalled, systemInterrupted: false).contains("SYS!"))
        #expect(CaptureWarningLabel.text(mic: .active, system: .recovered, systemInterrupted: true).contains("SYS GAP"))
        #expect(CaptureWarningLabel.text(mic: .active, system: .silent, systemInterrupted: false).contains("CHECK SYS"))
        #expect(CaptureWarningLabel.text(mic: .failed, system: .recovering, systemInterrupted: true).contains("MIC!"))
        #expect(MenuBarActivity.resolve(recording: false, transcriptionVisible: false, transcriptionFailed: false,
            captureIncomplete: true) == .captureIncomplete)
        #expect(MenuBarActivity.resolve(recording: true, transcriptionVisible: false, transcriptionFailed: false,
            captureIncomplete: true) == .recording)
        let build = AppBuildInfo.current(info: ["CFBundleShortVersionString": "0.1.5", "CFBundleVersion": "6", "RWSourceCommit": "fixture-sha"])
        #expect(build.display == "0.1.5 (build 6)")
        #expect(build.source_commit == "fixture-sha")
        #expect(AppBuildInfo.current(info: [:]).version == "development")
    }

    @Test("signal health checks the entire interleaved stereo buffer")
    func interleavedSignal() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
            channels: 2, interleaved: true))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 10))
        buffer.frameLength = 10
        let samples = try #require(buffer.floatChannelData)
        for sample in 0..<20 { samples[0][sample] = 0 }
        #expect(!SystemAudioRecorder.hasSignal(buffer))
        samples[0][19] = 0.5
        #expect(SystemAudioRecorder.hasSignal(buffer))
    }
}
