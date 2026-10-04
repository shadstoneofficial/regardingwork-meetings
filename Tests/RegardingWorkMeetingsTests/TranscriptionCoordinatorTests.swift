import AVFoundation
import Foundation
import Testing
@testable import RegardingWorkMeetings

private actor FixtureEngine: TranscriptionEngine {
    nonisolated let name = "fixture"
    nonisolated let model = "synthetic-only"
    enum Response: Sendable { case speech, empty, fail }
    enum Failure: Error { case transient }
    private var responses: [String: [Response]]
    private var counts: [String: Int] = [:]
    private var preparationFails: Bool

    init(_ responses: [String: [Response]] = [:], preparationFails: Bool = false) {
        self.responses = responses
        self.preparationFails = preparationFails
    }
    func prepare() throws { if preparationFails { throw Failure.transient } }
    func release() {}
    func calls(_ file: String) -> Int { counts[file, default: 0] }
    func transcribe(_ audio: URL) throws -> [TranscriptSegment] {
        let file = audio.lastPathComponent
        counts[file, default: 0] += 1
        var sequence = responses[file] ?? [.speech]
        let response = sequence.removeFirst()
        if !sequence.isEmpty { responses[file] = sequence }
        switch response {
        case .speech: return [TranscriptSegment(start: 0, end: 1, text: "synthetic \(file)")]
        case .empty: return []
        case .fail: throw Failure.transient
        }
    }
}

@Suite("Retryable per-track transcription")
struct TranscriptionCoordinatorTests {
    @Test("one failed track preserves successful output and retries only the failed work after relaunch")
    func partialRetry() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try session(root, name: "first")
        let engine = FixtureEngine(["system.caf": [.fail, .speech]])
        let first = coordinator(engine)
        await first.enqueue(session)
        try await wait(first)
        #expect(!exists(session, "transcript.json"))
        #expect(exists(session, "transcript.partial.json"))
        let progress = try readProgress(session)
        #expect(progress.state == "partial")
        #expect(progress.tracks.map(\.outcome) == [.transcribed, .failed])
        #expect(progress.tracks[0].segments.first?.text == "synthetic mic.caf")
        #expect(TranscriptionCoordinator.pendingDirectories(root: root).map { $0.resolvingSymlinksInPath().path }
            == [session.resolvingSymlinksInPath().path])
        let second = coordinator(engine)
        await second.resumePending(root: root)
        try await wait(second)
        #expect(exists(session, "transcript.json"))
        #expect(try readProgress(session).state == "complete")
        #expect(await engine.calls("mic.caf") == 1)
        #expect(await engine.calls("system.caf") == 2)
        #expect(try transcript(session).segments.count == 2)
        #expect(try mode(session.appendingPathComponent(TranscriptionProgress.filename)) == 0o600)
        #expect(try mode(session.appendingPathComponent("transcript.partial.json")) == 0o600)
        let log = try String(contentsOf: session.appendingPathComponent("transcribe.log"), encoding: .utf8)
        #expect(!log.contains("synthetic mic.caf"))
        #expect(!log.contains("synthetic system.caf"))
    }

    @Test("two inference failures stay unfinished while the next queued meeting completes")
    func backToBack() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try session(root, name: "first")
        let next = try session(root, name: "next")
        let engine = FixtureEngine(["mic.caf": [.fail, .speech], "system.caf": [.fail, .speech]])
        let runner = coordinator(engine)
        await runner.enqueue(first)
        await runner.enqueue(next)
        try await wait(runner)
        #expect(!exists(first, "transcript.json"))
        #expect(try readProgress(first).state == "failed")
        #expect(exists(next, "transcript.json"))
        #expect(TranscriptionCoordinator.pendingDirectories(root: root).map { $0.resolvingSymlinksInPath().path }
            == [first.resolvingSymlinksInPath().path])
    }

    @Test("missing, unreadable and empty audio have explicit unfinished states")
    func unavailableTracks() async throws {
        for availability in [AudioAvailability.missing, .unreadable, .empty] {
            let root = try folder()
            defer { try? FileManager.default.removeItem(at: root) }
            let session = try session(root, name: "unavailable")
            let runner = coordinator(FixtureEngine(), inspect: { _ in availability })
            await runner.enqueue(session)
            try await wait(runner)
            #expect(!exists(session, "transcript.json"))
            let expected: TranscriptionProgress.Outcome = switch availability {
            case .missing: .missing
            case .unreadable: .unreadable
            case .empty: .emptyAudio
            case .readable: .pending
            }
            #expect(try readProgress(session).tracks.allSatisfy { $0.outcome == expected })
        }
    }

    @Test("a readable track with no recognized speech completes with an explicit no-speech result")
    func noSpeech() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try session(root, name: "quiet")
        let runner = coordinator(FixtureEngine(["mic.caf": [.empty], "system.caf": [.empty]]))
        await runner.enqueue(session)
        try await wait(runner)
        #expect(exists(session, "transcript.json"))
        #expect(try readProgress(session).tracks.allSatisfy { $0.outcome == .noSpeech })
        #expect(try transcript(session).warnings.contains { $0.contains("no speech recognized") })
    }

    @Test("model preparation failure preserves a retryable checkpoint")
    func preparationFailure() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try session(root, name: "model-failure")
        let runner = coordinator(FixtureEngine(preparationFails: true))
        await runner.enqueue(session)
        try await wait(runner)
        #expect(!exists(session, "transcript.json"))
        #expect(try readProgress(session).state == "failed")
    }

    @Test("an existing completed transcript is never overwritten, even by direct enqueue")
    func completedIsPreserved() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try session(root, name: "completed")
        let sentinel = Data("existing successful transcript".utf8)
        try SecureStorage.write(sentinel, to: session.appendingPathComponent("transcript.json"))
        let engine = FixtureEngine()
        let runner = coordinator(engine)
        await runner.enqueue(session)
        #expect(await runner.retryPending(roots: [root]) == 0)
        try await wait(runner)
        #expect(try Data(contentsOf: session.appendingPathComponent("transcript.json")) == sentinel)
        #expect(await engine.calls("mic.caf") == 0)
    }

    @Test("audio inspection distinguishes a real empty CAF from missing and invalid data")
    func audioInspection() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(AudioAvailability.inspect(root.appendingPathComponent("missing.caf")) == .missing)
        let invalid = root.appendingPathComponent("invalid.caf")
        try SecureStorage.write(Data("not audio".utf8), to: invalid)
        #expect(AudioAvailability.inspect(invalid) == .unreadable)
        let url = root.appendingPathComponent("empty.caf")
        do {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            _ = try AVAudioFile(forWriting: url, settings: format.settings)
        }
        #expect(AudioAvailability.inspect(url) == .empty)
    }

    private func coordinator(_ engine: FixtureEngine,
        inspect: @escaping @Sendable (URL) -> AudioAvailability = { _ in .readable }
    ) -> TranscriptionCoordinator {
        TranscriptionCoordinator(engineFactory: { engine }, inspectAudio: inspect, enabled: { true },
            notification: { _, _ in }, completionHook: { _ in })
    }
    private func wait(_ runner: TranscriptionCoordinator) async throws {
        for _ in 0..<1_000 {
            if !(await runner.isProcessing) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("fixture transcription queue did not drain within 10 seconds")
    }
    private func folder() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rwm-inference-\(UUID())")
        try SecureStorage.createDirectory(directory)
        return directory
    }
    private func session(_ root: URL, name: String) throws -> URL {
        let directory = root.appendingPathComponent(name)
        try SecureStorage.createDirectory(directory)
        try SessionFileWriter.writeMetadata(SessionMetadata(schema_version: 1, session_id: name,
            started: "2026-10-04T00:00:00Z", ended: "2026-10-04T00:01:00Z", duration_seconds: 60,
            files: ["mic": "mic.caf", "system": "system.caf"], start_offset_ms: ["mic": 0, "system": 0],
            track_health: [:], recovered: false, recovery_note: nil, attribution: "source tracks"), to: directory)
        for name in ["mic.caf", "system.caf"] {
            try SecureStorage.write(Data("synthetic fixture".utf8), to: directory.appendingPathComponent(name))
        }
        return directory
    }
    private func exists(_ directory: URL, _ file: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path)
    }
    private func readProgress(_ directory: URL) throws -> TranscriptionProgress {
        try JSONDecoder().decode(TranscriptionProgress.self,
            from: Data(contentsOf: directory.appendingPathComponent(TranscriptionProgress.filename)))
    }
    private func transcript(_ directory: URL) throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: directory.appendingPathComponent("transcript.json")))
    }
    private func mode(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
