import Foundation
import Testing
@testable import RegardingWorkMeetings

@Suite("Session manifests and recovery")
struct SessionRecoveryTests {
    @Test("older metadata remains readable without microphone diagnostics")
    func decodesLegacyMetadata() throws {
        let data = Data(
            """
            {
              "schema_version": 1,
              "session_id": "legacy",
              "started": "2026-07-31T02:00:00Z",
              "ended": "2026-07-31T02:01:00Z",
              "duration_seconds": 60,
              "files": {"mic": "mic.caf", "system": "system.caf"},
              "start_offset_ms": {"mic": 0, "system": 0},
              "track_health": {},
              "recovered": false,
              "recovery_note": null,
              "attribution": "two-track source attribution"
            }
            """.utf8
        )
        let metadata = try JSONDecoder().decode(SessionMetadata.self, from: data)
        #expect(metadata.microphone_device_at_start == nil)
        #expect(metadata.microphone_configuration_restarts == nil)
        #expect(metadata.preserved_zero_filled_mic == nil)
    }

    @Test("interrupted session with one readable track is recovered without deletion")
    func recoversReadableTrack() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("2026.07.31-0900", isDirectory: true)
        try SecureStorage.createDirectory(session)
        let mic = session.appendingPathComponent("mic.caf")
        let system = session.appendingPathComponent("system.caf")
        try SecureStorage.write(Data("readable".utf8), to: mic)
        try SecureStorage.write(Data(), to: system)
        let manifest = RecordingManifest(
            schema_version: 1,
            state: "in_progress",
            session_id: "session-1",
            owner_pid: 123,
            started_at: "2026-07-31T02:00:00Z",
            files: ["mic": "mic.caf", "system": "system.caf"],
            first_buffer_at: ["mic": "2026-07-31T02:00:01Z"],
            track_health: [:]
        )
        try SessionFileWriter.writeManifest(manifest, to: session)

        let report = SessionRecovery.discover(
            root: root,
            now: ISO8601DateFormatter().date(from: "2026-07-31T02:10:00Z")!,
            processIsAlive: { _ in false },
            audioIsReadable: { $0.lastPathComponent == "mic.caf" }
        )

        #expect(report.recovered == ["2026.07.31-0900"])
        #expect(FileManager.default.fileExists(atPath: mic.path))
        #expect(FileManager.default.fileExists(atPath: system.path))
        #expect(
            FileManager.default.fileExists(
                atPath: session.appendingPathComponent("recording.recovered.json").path
            )
        )
        let metadata = try JSONDecoder().decode(
            SessionMetadata.self,
            from: Data(contentsOf: session.appendingPathComponent("meta.json"))
        )
        #expect(metadata.recovered)
        #expect(metadata.files == ["mic": "mic.caf", "system": "system.caf"])
        #expect(metadata.track_health["system"]?.state == .missing)
        #expect(metadata.duration_seconds == 0)
        #expect(metadata.microphone_device_at_end == nil)
    }

    @Test("apparently active or unreadable sessions remain untouched")
    func defersOrPreserves() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("session", isDirectory: true)
        try SecureStorage.createDirectory(session)
        let manifest = RecordingManifest(
            schema_version: 1,
            state: "in_progress",
            session_id: "session-2",
            owner_pid: 456,
            started_at: "2026-07-31T02:00:00Z",
            files: ["mic": "mic.caf"],
            first_buffer_at: [:],
            track_health: [:]
        )
        try SessionFileWriter.writeManifest(manifest, to: session)
        let active = SessionRecovery.discover(
            root: root,
            processIsAlive: { _ in true },
            audioIsReadable: { _ in true }
        )
        #expect(active.deferred == ["session"])
        #expect(!FileManager.default.fileExists(atPath: session.appendingPathComponent("meta.json").path))

        let unreadable = SessionRecovery.discover(
            root: root,
            processIsAlive: { _ in false },
            audioIsReadable: { _ in false }
        )
        #expect(unreadable.warnings.count == 1)
        #expect(FileManager.default.fileExists(atPath: session.appendingPathComponent("recording.json").path))
    }

    @Test("pending transcription discovery retries unfinished sessions only")
    func findsPendingTranscriptions() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let unfinished = root.appendingPathComponent("2026.08.19-1000", isDirectory: true)
        let completed = root.appendingPathComponent("2026.08.19-1100", isDirectory: true)
        let recording = root.appendingPathComponent("2026.08.19-1200", isDirectory: true)
        for directory in [unfinished, completed, recording] {
            try SecureStorage.createDirectory(directory)
        }
        try SecureStorage.write(
            Data("{}".utf8),
            to: unfinished.appendingPathComponent(SessionFileWriter.metadataName)
        )
        try SecureStorage.write(
            Data("{}".utf8),
            to: completed.appendingPathComponent(SessionFileWriter.metadataName)
        )
        try SecureStorage.write(
            Data("{}".utf8),
            to: completed.appendingPathComponent("transcript.json")
        )
        try SecureStorage.write(
            Data("{}".utf8),
            to: recording.appendingPathComponent(SessionFileWriter.manifestName)
        )

        #expect(
            TranscriptionCoordinator.pendingDirectories(root: root).map(\.lastPathComponent)
                == ["2026.08.19-1000"]
        )
        #expect(
            try Data(contentsOf: completed.appendingPathComponent("transcript.json"))
                == Data("{}".utf8)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rwm-recovery-\(UUID().uuidString)", isDirectory: true)
        try SecureStorage.createDirectory(url)
        return url
    }

    @Test("next-day recovery preserves digital silence, failures, routes and the original manifest")
    func historicalEvidence() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("interrupted")
        try SecureStorage.createDirectory(session)
        let device = AudioInputDeviceIdentity(id: 1, uid: "synthetic-mic", name: "Fixture input")
        let manifest = RecordingManifest(schema_version: 1, state: "in_progress", session_id: "historic", owner_pid: 1,
            started_at: "2026-10-03T00:00:00Z", files: ["mic": "mic.caf", "system": "system.caf"],
            first_buffer_at: ["mic": "2026-10-03T00:00:01Z", "system": "2026-10-03T00:00:00Z"],
            track_health: ["mic": TrackHealth(state: .digitalSilence, detail: "digital zeros"),
                "system": TrackHealth(state: .failed, detail: "write failed")],
            microphone_device: device, preserved_zero_filled_mic: "mic.zero-filled.caf",
            last_buffer_at: ["mic": "2026-10-03T00:01:00Z"], microphone_device_at_capture: device,
            microphone_route_history: [MicrophoneRouteObservation(observed_at: "2026-10-03T00:00:00Z", device: device)],
            track_health_history: ["mic": [TrackHealthObservation(observed_at: "2026-10-03T00:00:30Z",
                health: TrackHealth(state: .stalled, detail: "historical capture stalled"))]])
        try SessionFileWriter.writeManifest(manifest, to: session)
        let original = try Data(contentsOf: session.appendingPathComponent("recording.json"))
        let report = SessionRecovery.discover(root: root,
            now: ISO8601DateFormatter().date(from: "2026-10-04T00:00:00Z")!,
            processIsAlive: { _ in false }, audioIsReadable: { _ in true }, audioDuration: { _ in 65 })
        #expect(report.recovered == ["interrupted"])
        let metadata = try JSONDecoder().decode(SessionMetadata.self,
            from: Data(contentsOf: session.appendingPathComponent("meta.json")))
        #expect(metadata.duration_seconds == 66)
        #expect(metadata.ended == "2026-10-03T00:01:06Z")
        #expect(metadata.track_health["mic"]?.state == .digitalSilence)
        #expect(metadata.track_health["system"]?.state == .failed)
        #expect(metadata.microphone_device_at_end == device)
        #expect(metadata.microphone_route_history == manifest.microphone_route_history)
        #expect(metadata.track_health_history == manifest.track_health_history)
        #expect(metadata.preserved_zero_filled_mic == "mic.zero-filled.caf")
        let transcriptionMetadata = try SessionMeta.read(from: session)
        #expect(transcriptionMetadata.trackWarnings.contains("mic track historically reported stalled health"))
        #expect(transcriptionMetadata.trackWarnings.contains { $0.contains("zero-filled microphone attempt") })
        #expect(try Data(contentsOf: session.appendingPathComponent("recording.recovered.json")) == original)
    }

    @Test("recovery includes every system segment without collapsing the gap or replacing old audio")
    func segmentedRecovery() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("segmented-interruption")
        try SecureStorage.createDirectory(session)
        let old = session.appendingPathComponent("system.caf")
        let originalAudio = Data("synthetic original evidence".utf8)
        try SecureStorage.write(originalAudio, to: old)
        let manifest = RecordingManifest(schema_version: 1, state: "in_progress", session_id: "segments", owner_pid: 1,
            started_at: "2026-10-09T00:00:00Z", files: ["mic": "mic.caf", "system": "system.caf"],
            first_buffer_at: ["mic": "2026-10-09T00:00:00Z", "system": "2026-10-09T00:00:00Z"],
            track_health: ["system": TrackHealth(state: .recovering, detail: "restart underway")],
            last_buffer_at: ["mic": "2026-10-09T00:02:00Z"],
            system_audio_segments: [
                AudioCaptureSegment(file: "system.caf", started_at: "2026-10-09T00:00:00Z", offset_ms: 0,
                    first_buffer_at: "2026-10-09T00:00:00Z", capture_started: true),
                // Readable audio overrides stale 'not started' metadata after interruption.
                AudioCaptureSegment(file: "system.recovery-001.caf", started_at: "2026-10-09T00:01:00Z", offset_ms: 60_000)
            ],
            system_capture_interruptions: [CaptureInterruption(started_at: "2026-10-09T00:00:20Z",
                detected_at: "2026-10-09T00:00:36Z", reason: "stalled")], system_recovery_attempts: 1,
            app_build: AppBuildInfo(version: "0.1.5", build: "6", source_commit: "synthetic"))
        try SessionFileWriter.writeManifest(manifest, to: session)
        let manifestBytes = try Data(contentsOf: session.appendingPathComponent("recording.json"))
        let report = SessionRecovery.discover(root: root,
            now: ISO8601DateFormatter().date(from: "2026-10-10T00:00:00Z")!, processIsAlive: { _ in false },
            audioIsReadable: { _ in true }, audioDuration: { _ in 20 })
        #expect(report.recovered == ["segmented-interruption"])
        let metadata = try JSONDecoder().decode(SessionMetadata.self,
            from: Data(contentsOf: session.appendingPathComponent("meta.json")))
        #expect(metadata.duration_seconds == 120)
        #expect(metadata.system_audio_segments?.map(\.offset_ms) == [0, 60_000])
        #expect(metadata.system_audio_segments?.last?.capture_started == true)
        #expect(metadata.system_capture_interruptions == manifest.system_capture_interruptions)
        #expect(metadata.system_recovery_attempts == 1)
        #expect(metadata.app_build == manifest.app_build)
        #expect(try SessionMeta.read(from: session).tracks.map(\.file) == ["mic.caf", "system.caf", "system.recovery-001.caf"])
        #expect(try SessionMeta.read(from: session).captureIncomplete)
        #expect(try Data(contentsOf: old) == originalAudio)
        #expect(try Data(contentsOf: session.appendingPathComponent("recording.recovered.json")) == manifestBytes)
    }

    @Test("recovery refuses invalid segment paths and retains unreadable started segments for retry")
    func segmentValidationAndMissing() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("invalid")
        try SecureStorage.createDirectory(session)
        var manifest = RecordingManifest(schema_version: 1, state: "in_progress", session_id: "invalid", owner_pid: 1,
            started_at: "2026-10-09T00:00:00Z", files: ["mic": "mic.caf", "system": "system.caf"],
            first_buffer_at: [:], track_health: [:],
            system_audio_segments: [AudioCaptureSegment(file: "../system.caf", started_at: "2026-10-09T00:00:00Z", offset_ms: 0)])
        try SessionFileWriter.writeManifest(manifest, to: session)
        #expect(SessionRecovery.discover(root: root, processIsAlive: { _ in false }, audioIsReadable: { _ in true }).warnings.count == 1)
        #expect(!FileManager.default.fileExists(atPath: session.appendingPathComponent("meta.json").path))
        manifest.system_audio_segments = [AudioCaptureSegment(file: "system.recovery-001.caf",
            started_at: manifest.started_at, offset_ms: 0, capture_started: true)]
        try SessionFileWriter.writeManifest(manifest, to: session)
        #expect(SessionRecovery.discover(root: root, processIsAlive: { _ in false },
            audioIsReadable: { $0.lastPathComponent == "mic.caf" }, audioDuration: { _ in nil }).recovered == ["invalid"])
        let metadata = try SessionMeta.read(from: session)
        #expect(metadata.tracks.map(\.file) == ["mic.caf", "system.recovery-001.caf"])
        #expect(metadata.captureIncomplete)
    }
}
