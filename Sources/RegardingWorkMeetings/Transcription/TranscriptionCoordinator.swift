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
    private var engine: TranscriptionEngine?
    private var lastFailure: String?
    private var statusHandler: (@Sendable (Status) -> Void)?

    func setStatusHandler(_ handler: @escaping @Sendable (Status) -> Void) {
        statusHandler = handler
    }

    func enqueue(_ sessionDir: URL) {
        guard Config.transcriptionEnabled() else {
            runHook(for: sessionDir)
            return
        }
        if !queue.contains(sessionDir) { queue.append(sessionDir) }
        drainIfIdle()
    }

    func resumePending(root: URL) {
        guard Config.transcriptionEnabled() else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return }

        let manager = FileManager.default
        let pending = entries
            .filter {
                manager.fileExists(
                    atPath: $0.appendingPathComponent(SessionFileWriter.metadataName).path
                )
                    && !manager.fileExists(
                        atPath: $0.appendingPathComponent("transcript.json").path
                    )
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for directory in pending where !queue.contains(directory) {
            queue.append(directory)
        }
        if !pending.isEmpty {
            FileHandle.standardError.write(
                Data("resuming \(pending.count) untranscribed session(s)\n".utf8)
            )
        }
        drainIfIdle()
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
            publish(.transcribing(session: directory.lastPathComponent, queued: queue.count))
            do {
                try await transcribe(directory)
                notifyUser(
                    title: "\(AppIdentity.productName) — transcript ready",
                    body: directory.lastPathComponent
                )
                runHook(for: directory)
            } catch {
                log(directory, "transcription failed: \(error)")
                lastFailure = directory.lastPathComponent
                notifyUser(
                    title: "\(AppIdentity.productName) — transcription failed",
                    body: "\(directory.lastPathComponent) — see transcribe.log"
                )
            }
        }
        await engine?.release()
        engine = nil
        publish(lastFailure.map { .failed(session: $0) } ?? .idle)
        draining = false
        drainIfIdle()
    }

    private func transcribe(_ directory: URL) async throws {
        let metadata = try SessionMeta.read(from: directory)
        let engine = try await preparedEngine()

        var trackTranscripts: [TrackTranscript] = []
        var warnings: [String] = metadata.trackWarnings
        for track in metadata.tracks {
            let audio = directory.appendingPathComponent(track.file)
            guard FileManager.default.fileExists(atPath: audio.path) else {
                let warning = "\(track.file) is missing; transcript may be incomplete"
                warnings.append(warning)
                log(directory, warning)
                continue
            }
            log(directory, "transcribing \(track.file) (\(engine.name))")
            let segments: [TranscriptSegment]
            do {
                segments = try await engine.transcribe(audio)
            } catch {
                let warning = "\(track.file) was unreadable; transcript may be incomplete"
                warnings.append(warning)
                log(directory, "\(warning): \(error)")
                continue
            }
            trackTranscripts.append(
                TrackTranscript(
                    speaker: track.speaker,
                    offsetMs: track.offsetMs,
                    segments: segments
                )
            )
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
        try transcript.write(to: directory)
        log(
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
        let engine = ParakeetEngine()
        try await engine.prepare()
        self.engine = engine
        return engine
    }

    /// Executes only a trusted argv array from the user's config. No shell is
    /// involved, and no metadata or transcript content can become executable.
    private func runHook(for directory: URL) {
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

    private func log(_ directory: URL, _ message: String) {
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
    struct Track: Equatable {
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
    func write(to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let markdown = Data(rendered(title: directory.lastPathComponent).utf8)
        let json = try encoder.encode(self)
        try SecureStorage.write(markdown, to: directory.appendingPathComponent("transcript.md"))
        try SecureStorage.write(json, to: directory.appendingPathComponent("transcript.json"))
    }

    func rendered(title: String) -> String {
        var lines = [
            "# \(title)",
            "",
            "engine: \(engine) (\(model))",
            "",
            "> Attribution: \(attribution).",
            "",
        ]
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
