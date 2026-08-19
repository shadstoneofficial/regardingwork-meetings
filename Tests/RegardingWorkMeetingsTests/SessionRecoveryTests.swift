import Foundation
import Testing
@testable import RegardingWorkMeetings

@Suite("Session manifests and recovery")
struct SessionRecoveryTests {
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
        #expect(metadata.files == ["mic": "mic.caf"])
        #expect(metadata.track_health["system"]?.state == .missing)
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
}
