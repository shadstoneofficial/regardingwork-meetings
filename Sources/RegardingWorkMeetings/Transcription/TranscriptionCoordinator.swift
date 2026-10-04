import Foundation

/// Serial, on-device post-processing. The filesystem remains the queue:
/// meta.json without transcript.json is pending and is retried after relaunch.
actor TranscriptionCoordinator {
    enum Status: Sendable {
        case idle
        case transcribing(session: String, queued: Int)
        case failed(session: String)
    }

    private var queue: [URL] = []
    private var draining = false
    private var currentDirectory: URL?
    private var engine: TranscriptionEngine?
    private var lastFailure: String?
    private var statusHandler: (@Sendable (Status) -> Void)?
    private let engineFactory: @Sendable () -> any TranscriptionEngine
    private let inspectAudio: @Sendable (URL) -> AudioAvailability
    private let enabled: @Sendable () -> Bool
    private let notification: @Sendable (String, String) -> Void
    private let completionHook: @Sendable (URL) -> Void

    init(
        engineFactory: @escaping @Sendable () -> any TranscriptionEngine = { ParakeetEngine() },
        inspectAudio: @escaping @Sendable (URL) -> AudioAvailability = AudioAvailability.inspect,
        enabled: @escaping @Sendable () -> Bool = Config.transcriptionEnabled,
        notification: @escaping @Sendable (String, String) -> Void = { notifyUser(title: $0, body: $1) },
        completionHook: @escaping @Sendable (URL) -> Void = TranscriptionCoordinator.runConfiguredHook
    ) {
        self.engineFactory = engineFactory
        self.inspectAudio = inspectAudio
        self.enabled = enabled
        self.notification = notification
        self.completionHook = completionHook
    }

    var isProcessing: Bool { draining }

    func setStatusHandler(_ handler: @escaping @Sendable (Status) -> Void) {
        statusHandler = handler
    }

    func enqueue(_ sessionDir: URL) {
        guard enabled() else {
            completionHook(sessionDir)
            return
        }
        let directory = Self.canonicalDirectory(sessionDir)
        guard directory != currentDirectory, !Self.isCompleted(directory) else { return }
        if !queue.contains(directory) { queue.append(directory) }
        drainIfIdle()
    }

    func resumePending(root: URL) {
        guard enabled() else { return }
        let pending = Self.pendingDirectories(root: root)
        for directory in pending
        where directory != currentDirectory && !queue.contains(directory) {
            queue.append(directory)
        }
        if !pending.isEmpty {
            FileHandle.standardError.write(
                Data("resuming \(pending.count) untranscribed session(s)\n".utf8)
            )
        }
        drainIfIdle()
    }

    /// Re-scan all configured discovery roots and queue every unfinished
    /// session. A completed transcript.json is the final marker and is never
    /// overwritten by this action.
    func retryPending(roots: [URL]) -> Int {
        guard enabled() else { return 0 }
        let candidates = roots
            .flatMap(Self.pendingDirectories(root:))
            .sorted { $0.path < $1.path }
        var added = 0
        for directory in candidates
        where directory != currentDirectory && !queue.contains(directory) {
            queue.append(directory)
            added += 1
        }
        if added > 0 {
            lastFailure = nil
            FileHandle.standardError.write(
                Data("retrying \(added) unfinished transcription(s)\n".utf8)
            )
        }
        drainIfIdle()
        return added
    }

    static func pendingDirectories(root: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        let manager = FileManager.default
        return entries
            .filter {
                manager.fileExists(
                    atPath: $0.appendingPathComponent(SessionFileWriter.metadataName).path
                )
                    && !Self.isCompleted($0)
            }
            .map(Self.canonicalDirectory)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func isCompleted(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("transcript.json").path)
    }

    private static func canonicalDirectory(_ directory: URL) -> URL {
        URL(fileURLWithPath: directory.resolvingSymlinksInPath().path, isDirectory: true)
    }

    private func drainIfIdle() {
        guard !draining, !queue.isEmpty else { return }
        draining = true
        lastFailure = nil
        Task { await drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            let directory = queue.removeFirst()
            currentDirectory = directory
            publish(.transcribing(session: directory.lastPathComponent, queued: queue.count))
            do {
                guard !Self.isCompleted(directory) else {
                    currentDirectory = nil
                    continue
                }
                try await transcribe(directory)
                notification("\(AppIdentity.productName) — transcript ready", directory.lastPathComponent)
                completionHook(directory)
            } catch {
                Self.log(directory, "transcription unfinished (\(String(reflecting: type(of: error)))); retry available")
                lastFailure = directory.lastPathComponent
                notification("\(AppIdentity.productName) — transcription needs attention",
                    "\(directory.lastPathComponent) — see transcribe.log; Retry unfinished transcriptions is available")
            }
            currentDirectory = nil
        }
        await engine?.release()
        engine = nil
        publish(lastFailure.map { .failed(session: $0) } ?? .idle)
        draining = false
        drainIfIdle()
    }

    private func transcribe(_ directory: URL) async throws {
        let metadata = try SessionMeta.read(from: directory)
        guard !metadata.tracks.isEmpty else { throw TranscriptionProgress.ProgressError.changedSources }
        var progress = try TranscriptionProgress.load(directory: directory, sources: metadata.tracks)
        let engine: any TranscriptionEngine
        do {
            engine = try await preparedEngine()
        } catch {
            progress.state = "failed"
            try progress.write(to: directory)
            throw error
        }
        if let previous = progress.engine, let model = progress.model,
           previous != engine.name || model != engine.model {
            throw TranscriptionProgress.ProgressError.incompatibleEngine
        }
        progress.engine = engine.name
        progress.model = engine.model
        var warnings: [String] = metadata.trackWarnings
        for index in progress.tracks.indices {
            if progress.tracks[index].outcome.succeeded { continue }
            let track = progress.tracks[index].source
            let audio = directory.appendingPathComponent(track.file)
            progress.tracks[index].failure_class = nil
            switch inspectAudio(audio) {
            case .missing: progress.tracks[index].outcome = .missing
            case .empty: progress.tracks[index].outcome = .emptyAudio
            case .unreadable: progress.tracks[index].outcome = .unreadable
            case .readable:
                Self.log(directory, "transcribing \(track.file) (\(engine.name))")
                do {
                    let segments = try await engine.transcribe(audio)
                    progress.tracks[index].segments = segments
                    progress.tracks[index].outcome = segments.isEmpty ? .noSpeech : .transcribed
                } catch {
                    progress.tracks[index].outcome = .failed
                    progress.tracks[index].failure_class = String(reflecting: type(of: error))
                }
            }
            progress.state = "partial"
            try progress.write(to: directory)
        }
        let complete = progress.tracks.allSatisfy { $0.outcome.succeeded }
        for track in progress.tracks where track.outcome != .transcribed {
            warnings.append("\(track.source.file): \(track.outcome.rawValue)"
                + (track.outcome.succeeded ? " (no speech recognized)" : "; unfinished and retryable"))
        }
        let trackTranscripts = progress.tracks.filter { $0.outcome.succeeded }.map {
            TrackTranscript(speaker: $0.source.speaker, offsetMs: $0.source.offsetMs, segments: $0.segments)
        }
        var merged = TranscriptMerger.merge(trackTranscripts)
        let duplicateResult = DuplicateDetector.annotate(merged)
        merged = duplicateResult.segments
        if duplicateResult.warningCount > 0 {
            warnings.append(
                "\(duplicateResult.warningCount) possible cross-track playback echo pair(s) retained"
            )
        }
        if duplicateResult.suppressedCount > 0 {
            warnings.append(
                "\(duplicateResult.suppressedCount) high-confidence microphone echo segment(s) "
                    + "hidden from Markdown but preserved in transcript.json"
            )
        }

        let transcript = Transcript(
            engine: engine.name,
            model: engine.model,
            created_at: ISO8601DateFormatter().string(from: Date()),
            attribution: "microphone=me and system=them are source tracks, not multi-speaker diarization",
            warnings: warnings,
            segments: merged
        )
        progress.state = complete ? "complete" : (trackTranscripts.isEmpty ? "failed" : "partial")
        try progress.write(to: directory)
        try transcript.write(to: directory, partial: !complete)
        guard complete else { throw TranscriptionProgress.ProgressError.unfinishedTracks }
        Self.log(
            directory,
            "done — \(merged.count) segments, \(warnings.count) warning(s), "
                + "\(duplicateResult.suppressedCount) high-confidence echo suppression(s)"
        )
    }

    private func preparedEngine() async throws -> TranscriptionEngine {
        if let engine { return engine }
        let configured = Config.transcriptionEngine()
        if configured != "parakeet" {
            FileHandle.standardError.write(
                Data(
                    "warning: unknown transcription engine \"\(configured)\" — using parakeet\n".utf8
                )
            )
        }
        let engine = engineFactory()
        try await engine.prepare()
        self.engine = engine
        return engine
    }

    /// Executes only a trusted argv array from the user's config. No shell is
    /// involved, and no metadata or transcript content can become executable.
    private static func runConfiguredHook(_ directory: URL) {
        guard let command = Config.onStop() else { return }
        let invocation = command.invocation(sessionDirectory: directory)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: invocation.executable)
        task.arguments = invocation.arguments
        do {
            try task.run()
        } catch {
            log(directory, "on_stop hook failed to launch: \(error)")
        }
    }

    private static func log(_ directory: URL, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        do {
            try SecureStorage.append(
                Data(line.utf8),
                to: directory.appendingPathComponent("transcribe.log")
            )
        } catch {
            FileHandle.standardError.write(Data("session log write failed: \(error)\n".utf8))
        }
    }

    private func publish(_ status: Status) {
        statusHandler?(status)
    }
}

struct TrackTranscript: Sendable {
    let speaker: String
    let offsetMs: Int
    let segments: [TranscriptSegment]
}

enum TranscriptMerger {
    static func merge(_ tracks: [TrackTranscript]) -> [Transcript.Segment] {
        var merged = tracks.flatMap { track in
            let offset = TimeInterval(track.offsetMs) / 1_000
            return track.segments.map {
                Transcript.Segment(
                    speaker: track.speaker,
                    start_ms: Int(($0.start + offset) * 1_000),
                    end_ms: Int(($0.end + offset) * 1_000),
                    text: $0.text,
                    suspected_echo: false,
                    suppressed_as_echo: false,
                    echo_match_confidence: nil
                )
            }
        }
        merged.sort {
            $0.start_ms == $1.start_ms
                ? $0.speaker < $1.speaker
                : $0.start_ms < $1.start_ms
        }
        return merged
    }
}

struct SessionMeta: Equatable {
    struct Track: Codable, Equatable, Sendable {
        let file: String
        let speaker: String
        let offsetMs: Int
    }

    let tracks: [Track]
    let trackWarnings: [String]

    enum MetaError: Error, CustomStringConvertible {
        case unreadable(URL)

        var description: String {
            switch self {
            case .unreadable(let url): return "can't parse \(url.path)"
            }
        }
    }

    static func read(from directory: URL) throws -> SessionMeta {
        let url = directory.appendingPathComponent(SessionFileWriter.metadataName)
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let files = json["files"] as? [String: String]
        else { throw MetaError.unreadable(url) }

        let offsets = json["start_offset_ms"] as? [String: Int] ?? [:]
        var tracks: [Track] = []
        if let microphone = files["mic"] {
            tracks.append(
                Track(file: microphone, speaker: "me", offsetMs: offsets["mic"] ?? 0)
            )
        }
        if let system = files["system"] {
            tracks.append(
                Track(file: system, speaker: "them", offsetMs: offsets["system"] ?? 0)
            )
        }
        guard tracks.allSatisfy({
            !$0.file.isEmpty && $0.file == URL(fileURLWithPath: $0.file).lastPathComponent
                && !$0.file.hasPrefix(".")
        }) else { throw MetaError.unreadable(url) }

        var warnings: [String] = []
        if let health = json["track_health"] as? [String: [String: Any]] {
            for track in ["mic", "system"] {
                guard
                    let value = health[track],
                    let state = value["state"] as? String,
                    !["active", "recovered"].contains(state)
                else { continue }
                warnings.append("\(track) track ended with \(state) health")
            }
        }
        if let history = json["track_health_history"] as? [String: [[String: Any]]] {
            for track in ["mic", "system"] {
                let states = (history[track] ?? []).compactMap { ($0["health"] as? [String: Any])?["state"] as? String }
                for state in Set(states).sorted() where !["active", "recovered", "starting"].contains(state) {
                    warnings.append("\(track) track historically reported \(state) health")
                }
            }
        }
        if json["preserved_zero_filled_mic"] as? String != nil {
            warnings.append("a zero-filled microphone attempt was preserved; inspect the original audio")
        }
        return SessionMeta(tracks: tracks, trackWarnings: warnings)
    }
}

struct Transcript: Codable, Equatable {
    struct Segment: Codable, Equatable {
        let speaker: String
        let start_ms: Int
        let end_ms: Int
        let text: String
        var suspected_echo: Bool
        var suppressed_as_echo: Bool
        var echo_match_confidence: Double?
    }

    let engine: String
    let model: String
    let created_at: String
    let attribution: String
    let warnings: [String]
    let segments: [Segment]

    /// Markdown is written first and transcript.json last. The JSON file is
    /// the completion marker, so a Markdown failure remains retryable.
    func write(to directory: URL, partial: Bool = false) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let markdown = Data(rendered(title: directory.lastPathComponent, partial: partial).utf8)
        let json = try encoder.encode(self)
        let stem = partial ? "transcript.partial" : "transcript"
        try SecureStorage.write(markdown, to: directory.appendingPathComponent("\(stem).md"))
        try SecureStorage.write(json, to: directory.appendingPathComponent("\(stem).json"))
    }

    func rendered(title: String, partial: Bool = false) -> String {
        var lines = [
            "# \(title)",
            "",
            "engine: \(engine) (\(model))",
            "",
            "> Attribution: \(attribution).",
            "",
        ]
        if partial {
            lines += ["> PARTIAL / UNFINISHED: successful track output is preserved; retry the unfinished tracks.", ""]
        }
        if !warnings.isEmpty {
            lines.append("## Recording and transcript warnings")
            lines.append("")
            for warning in warnings { lines.append("- \(warning)") }
            lines.append("")
        }
        for segment in segments where !segment.suppressed_as_echo {
            let echo = segment.suspected_echo ? " ⚠︎ possible playback echo" : ""
            lines.append(
                "**[\(Self.clock(segment.start_ms))] \(segment.speaker):** "
                    + "\(segment.text)\(echo)"
            )
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func clock(_ milliseconds: Int) -> String {
        let total = milliseconds / 1000
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

struct DuplicateDetectionResult: Equatable {
    let segments: [Transcript.Segment]
    let warningCount: Int
    let suppressedCount: Int
}

enum DuplicateDetector {
    static let warningThreshold = 0.78
    static let suppressionThreshold = 0.92
    static let timingToleranceMs = 1_500

    static func annotate(_ input: [Transcript.Segment]) -> DuplicateDetectionResult {
        var segments = input
        var warnings = 0
        var suppressed = 0
        for micIndex in segments.indices where segments[micIndex].speaker == "me" {
            var best: (index: Int, confidence: Double)?
            for systemIndex in segments.indices where segments[systemIndex].speaker == "them" {
                guard overlaps(segments[micIndex], segments[systemIndex]) else { continue }
                let confidence = similarity(
                    segments[micIndex].text,
                    segments[systemIndex].text
                )
                if best == nil || confidence > best!.confidence {
                    best = (systemIndex, confidence)
                }
            }
            guard let best, best.confidence >= warningThreshold else { continue }
            warnings += 1
            segments[micIndex].suspected_echo = true
            segments[micIndex].echo_match_confidence =
                Double(round(best.confidence * 1_000) / 1_000)
            if best.confidence >= suppressionThreshold {
                segments[micIndex].suppressed_as_echo = true
                suppressed += 1
            }
        }
        return DuplicateDetectionResult(
            segments: segments,
            warningCount: warnings,
            suppressedCount: suppressed
        )
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let left = tokens(lhs)
        let right = tokens(rhs)
        guard min(left.count, right.count) >= 4 else { return 0 }
        let distance = editDistance(left, right)
        return 1 - Double(distance) / Double(max(left.count, right.count))
    }

    private static func overlaps(_ lhs: Transcript.Segment, _ rhs: Transcript.Segment) -> Bool {
        max(lhs.start_ms, rhs.start_ms) <= min(lhs.end_ms, rhs.end_ms) + timingToleranceMs
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        var previous = Array(0...rhs.count)
        for (leftIndex, left) in lhs.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, right) in rhs.enumerated() {
                current.append(
                    min(
                        current[rightIndex] + 1,
                        previous[rightIndex + 1] + 1,
                        previous[rightIndex] + (left == right ? 0 : 1)
                    )
                )
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
