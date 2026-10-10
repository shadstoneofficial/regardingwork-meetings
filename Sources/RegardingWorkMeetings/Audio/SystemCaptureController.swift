import Foundation

protocol SystemAudioRecording: AnyObject {
    var ownsOutputFile: Bool { get }
    func start(writingToNewFile url: URL, beforeCapture: () throws -> Void) throws
    func stop()
    func snapshot() -> RecorderSnapshot
}

/// Driven synchronously by the session's common-mode watchdog, never by an orphan timer.
/// Only an already visible, user-started session may rebuild a stalled tap.
final class SystemCaptureController {
    static let maximumRecoveryAttempts = 3
    private let directory: URL
    private let sessionStartedAt: Date
    private let factory: () -> any SystemAudioRecording
    private var recorder: (any SystemAudioRecording)?
    private var active = false
    private var pendingAt: TimeInterval?
    private var terminalFailure: String?
    private var failedStartIsRetryable = false
    private var records: [AudioCaptureSegment] = []
    private(set) var recoveryAttempts = 0
    private(set) var interruptions: [CaptureInterruption] = []
    var beforeCapture: (() throws -> Void)?

    init(directory: URL, startedAt: Date, factory: @escaping () -> any SystemAudioRecording = { SystemAudioRecorder() }) {
        self.directory = directory
        self.sessionStartedAt = startedAt
        self.factory = factory
    }

    deinit { stop() }

    var wasInterrupted: Bool { !interruptions.isEmpty }
    var firstBufferAt: Date? { bufferDates(first: true).min() }
    var lastBufferAt: Date? { bufferDates(first: false).max() }

    func start(now: Date = Date()) throws {
        guard !active else { return }
        active = true
        do { try beginSegment(filename: "system.caf", now: now) }
        catch { stop(); throw error }
    }

    func stop() {
        active = false
        pendingAt = nil
        closeSegment()
    }

    func segments(origin: Date) -> [AudioCaptureSegment] {
        refreshSegment()
        let iso = ISO8601DateFormatter()
        return records.map { record in
            var copy = record
            let start = record.first_buffer_at.flatMap(iso.date(from:))
                ?? iso.date(from: record.started_at) ?? sessionStartedAt
            copy.offset_ms = max(0, Int(start.timeIntervalSince(origin) * 1_000))
            return copy
        }
    }

    func health(now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
                allowRecovery: Bool = true) -> TrackHealth {
        refreshSegment()
        guard active else {
            return TrackHealth(state: .failed, detail: terminalFailure ?? "system capture is stopped")
        }
        if let terminalFailure {
            return TrackHealth(state: .failed, detail: terminalFailure)
        }
        if let scheduled = pendingAt {
            guard allowRecovery, uptime >= scheduled else {
                return TrackHealth(state: .recovering, detail: "system capture interrupted; restart scheduled; microphone continues")
            }
            pendingAt = nil
            recoveryAttempts += 1
            do {
                try beginSegment(filename: nextFilename(), now: now)
                return TrackHealth(state: .recovering,
                    detail: "system restart \(recoveryAttempts)/\(Self.maximumRecoveryAttempts); waiting for new audio")
            } catch {
                let detail = "system restart failed: \(error)"
                if failedStartIsRetryable { scheduleOrFail(detail: detail, uptime: uptime) }
                else { terminalFailure = detail + "; restart could not start safely; check storage and recovery manifest" }
                return TrackHealth(state: .failed, detail: terminalFailure ?? detail + "; retry scheduled")
            }
        }
        guard let recorder, let current = records.last else {
            return TrackHealth(state: .failed, detail: "system recorder unavailable")
        }
        let snapshot = recorder.snapshot()
        let segmentStart = ISO8601DateFormatter().date(from: current.started_at) ?? now
        let health = TrackHealthEvaluator.evaluate(snapshot: snapshot, sessionStartedAt: segmentStart, now: now)
        if health.state == .stalled || health.state == .failed {
            guard allowRecovery else { return health }
            interruptions.append(CaptureInterruption(
                started_at: ISO8601DateFormatter().string(from: snapshot.lastBufferAt ?? segmentStart),
                detected_at: ISO8601DateFormatter().string(from: now), reason: health.detail
            ))
            closeSegment()
            if health.state == .failed && !snapshot.retryableFailure {
                terminalFailure = health.detail + "; capture stopped to preserve audio; check storage and start a new recording"
            } else {
                scheduleOrFail(detail: health.detail, uptime: uptime)
            }
            return TrackHealth(state: health.state, detail: terminalFailure ?? health.detail + "; safe restart scheduled")
        }
        if let first = snapshot.firstBufferAt, !interruptions.isEmpty,
           interruptions[interruptions.count - 1].resumed_at == nil {
            interruptions[interruptions.count - 1].resumed_at = ISO8601DateFormatter().string(from: first)
        }
        if recoveryAttempts > 0 && health.state == .starting {
            return TrackHealth(state: .recovering, detail: "waiting for the restarted system track's first buffer")
        }
        if wasInterrupted && health.state == .active {
            return TrackHealth(state: .recovered, detail: "new system audio detected; earlier capture gap retained")
        }
        return health
    }

    private func scheduleOrFail(detail: String, uptime: TimeInterval) {
        if recoveryAttempts < Self.maximumRecoveryAttempts {
            pendingAt = uptime + Double(2 << recoveryAttempts)
        } else {
            terminalFailure = detail + "; automatic recovery exhausted (3 attempts); stop/save and start a new recording"
        }
    }

    private func beginSegment(filename: String, now: Date) throws {
        failedStartIsRetryable = false
        let newRecorder = factory()
        records.append(AudioCaptureSegment(file: filename,
            started_at: ISO8601DateFormatter().string(from: now), offset_ms: 0))
        recorder = newRecorder
        do {
            try newRecorder.start(writingToNewFile: directory.appendingPathComponent(filename)) {
                records[records.count - 1].capture_started = true
                try beforeCapture?()
            }
        } catch {
            failedStartIsRetryable = newRecorder.snapshot().retryableFailure
            refreshSegment()
            if !newRecorder.ownsOutputFile {
                records.removeLast() // Never claim somebody else's colliding file as our audio.
            } else {
                records[records.count - 1].capture_started = false
                records[records.count - 1].failure = "system segment could not start: \(error)"
            }
            newRecorder.stop()
            recorder = nil
            throw error
        }
    }

    private func closeSegment() {
        refreshSegment()
        recorder?.stop()
        refreshSegment()
        recorder = nil
    }

    private func refreshSegment() {
        guard let recorder, !records.isEmpty else { return }
        let snapshot = recorder.snapshot()
        let index = records.count - 1
        let iso = ISO8601DateFormatter()
        if let first = snapshot.firstBufferAt { records[index].first_buffer_at = iso.string(from: first) }
        if let last = snapshot.lastBufferAt { records[index].last_buffer_at = iso.string(from: last) }
        records[index].frames_written = snapshot.framesWritten
        records[index].sample_rate = snapshot.sampleRate
        if let failure = snapshot.failure { records[index].failure = failure }
    }

    private func bufferDates(first: Bool) -> [Date] {
        refreshSegment()
        let iso = ISO8601DateFormatter()
        return records.compactMap { (first ? $0.first_buffer_at : $0.last_buffer_at).flatMap(iso.date(from:)) }
    }

    private func nextFilename() -> String {
        var index = records.count
        while true {
            let name = String(format: "system.recovery-%03d.caf", index)
            if !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) { return name }
            index += 1
        }
    }
}
