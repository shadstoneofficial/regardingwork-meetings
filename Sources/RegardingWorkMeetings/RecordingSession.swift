import Foundation

/// One local meeting session. Microphone=`me` and system=`them` describe the
/// source track; they are not true multi-speaker diarization.
final class RecordingSession {
    let dir: URL
    let startedAt: Date

    private let sessionID = UUID().uuidString
    private let mic = MicRecorder()
    private let system = SystemAudioRecorder()
    private var lastManifestWrite = Date.distantPast

    private static let folderFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd-HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(root: URL, now: Date = Date()) throws {
        startedAt = now
        try SecureStorage.createDirectory(root)
        let base = Self.folderFormat.string(from: startedAt)
        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try SecureStorage.createDirectory(candidate)
        dir = candidate
    }

    /// Writes the crash-recovery sidecar before capture starts, then starts
    /// both independent tracks. A failed start is finalized as a visible,
    /// non-transcribable session instead of leaving an ambiguous folder.
    func start() throws {
        try writeManifest(health: initialHealth())
        do {
            try system.start(writingTo: audioURL("system"))
            try mic.start(writingTo: audioURL("mic"))
        } catch {
            mic.stop()
            system.stop()
            _ = finalize(
                endedAt: Date(),
                health: [
                    "mic": TrackHealth(state: .failed, detail: "\(error)"),
                    "system": TrackHealth(state: .failed, detail: "session start was aborted"),
                ],
                recoveryNote: "Recording did not start successfully."
            )
            throw error
        }
    }

    /// Current health is safe to display while recording. A track is only
    /// active when both buffers and an audible signal have been observed.
    @discardableResult
    func health(now: Date = Date(), persist: Bool = true) -> [String: TrackHealth] {
        let result = [
            "mic": TrackHealthEvaluator.evaluate(
                snapshot: mic.snapshot(),
                sessionStartedAt: startedAt,
                now: now
            ),
            "system": TrackHealthEvaluator.evaluate(
                snapshot: system.snapshot(),
                sessionStartedAt: startedAt,
                now: now
            ),
        ]
        if persist, now.timeIntervalSince(lastManifestWrite) >= 5 {
            try? writeManifest(health: result)
            lastManifestWrite = now
        }
        return result
    }

    /// Stops both tracks and writes final metadata before removing the
    /// in-progress sidecar. If metadata cannot be written, recording.json is
    /// deliberately left in place for recovery.
    @discardableResult
    func stop(now: Date = Date()) -> SessionMetadata {
        let finalHealth = health(now: now, persist: false)
        mic.stop()
        system.stop()
        return finalize(endedAt: now, health: finalHealth, recoveryNote: nil)
    }

    private func finalize(
        endedAt: Date,
        health: [String: TrackHealth],
        recoveryNote: String?
    ) -> SessionMetadata {
        let iso = ISO8601DateFormatter()
        let micStart = mic.firstBufferAt ?? startedAt
        let systemStart = system.firstBufferAt ?? startedAt
        let earliest = min(micStart, systemStart)
        let metadata = SessionMetadata(
            schema_version: 1,
            session_id: sessionID,
            started: iso.string(from: startedAt),
            ended: iso.string(from: endedAt),
            duration_seconds: max(0, Int(endedAt.timeIntervalSince(startedAt))),
            files: ["mic": "mic.caf", "system": "system.caf"],
            start_offset_ms: [
                "mic": max(0, Int(micStart.timeIntervalSince(earliest) * 1000)),
                "system": max(0, Int(systemStart.timeIntervalSince(earliest) * 1000)),
            ],
            track_health: health,
            recovered: false,
            recovery_note: recoveryNote,
            attribution: "two-track source attribution (microphone=me, system=them), not speaker diarization"
        )
        do {
            try SessionFileWriter.writeMetadata(metadata, to: dir)
            try? FileManager.default.removeItem(
                at: dir.appendingPathComponent(SessionFileWriter.manifestName)
            )
            for track in ["mic", "system"] {
                try? SecureStorage.protectFile(audioURL(track))
            }
        } catch {
            FileHandle.standardError.write(
                Data("metadata write failed; recovery manifest preserved: \(error)\n".utf8)
            )
        }
        return metadata
    }

    private func writeManifest(health: [String: TrackHealth]) throws {
        let iso = ISO8601DateFormatter()
        var firstBuffers: [String: String] = [:]
        if let first = mic.firstBufferAt { firstBuffers["mic"] = iso.string(from: first) }
        if let first = system.firstBufferAt { firstBuffers["system"] = iso.string(from: first) }
        let manifest = RecordingManifest(
            schema_version: 1,
            state: "in_progress",
            session_id: sessionID,
            owner_pid: getpid(),
            started_at: iso.string(from: startedAt),
            files: ["mic": "mic.caf", "system": "system.caf"],
            first_buffer_at: firstBuffers,
            track_health: health
        )
        try SessionFileWriter.writeManifest(manifest, to: dir)
    }

    private func initialHealth() -> [String: TrackHealth] {
        [
            "mic": TrackHealth(state: .starting, detail: "capture has not started"),
            "system": TrackHealth(state: .starting, detail: "capture has not started"),
        ]
    }

    private func audioURL(_ track: String) -> URL {
        dir.appendingPathComponent("\(track).caf")
    }
}
