import Foundation
import Testing
@testable import RegardingWorkMeetings

@Suite("Transcript integrity")
struct TranscriptTests {
    @Test("track offsets are applied and segments are deterministically ordered")
    func mergingAndOrdering() {
        let merged = TranscriptMerger.merge([
            TrackTranscript(
                speaker: "me",
                offsetMs: 500,
                segments: [
                    TranscriptSegment(start: 1, end: 2, text: "second"),
                ]
            ),
            TrackTranscript(
                speaker: "them",
                offsetMs: 0,
                segments: [
                    TranscriptSegment(start: 0.5, end: 1, text: "first"),
                    TranscriptSegment(start: 1.5, end: 2, text: "tie"),
                ]
            ),
        ])
        #expect(merged.map(\.text) == ["first", "second", "tie"])
        #expect(merged.map(\.start_ms) == [500, 1_500, 1_500])
    }

    @Test("high-confidence playback echo is hidden only in Markdown")
    func conservativeDuplicateSuppression() {
        let result = DuplicateDetector.annotate([
            segment("them", 1_000, 4_000, "Thanks so much for joining our meeting today"),
            segment("me", 1_100, 4_100, "Thanks so much for joining our meeting today"),
            segment("me", 1_200, 4_200, "Thanks for joining but I have a different concern"),
        ])
        #expect(result.suppressedCount == 1)
        #expect(result.segments[1].suppressed_as_echo)
        #expect(!result.segments[2].suppressed_as_echo)
        #expect(result.segments.count == 3)
    }

    @Test("short or weak matches are retained")
    func weakMatchesRemain() {
        #expect(DuplicateDetector.similarity("yes thanks", "yes thanks") == 0)
        let result = DuplicateDetector.annotate([
            segment("them", 0, 2_000, "The budget review starts after lunch today"),
            segment("me", 0, 2_000, "I need to discuss a different project today"),
        ])
        #expect(result.suppressedCount == 0)
        #expect(result.warningCount == 0)
    }

    @Test("Markdown warns, labels source attribution, and JSON is final completion marker")
    func renderingAndPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rwm-transcript-\(UUID().uuidString)", isDirectory: true)
        try SecureStorage.createDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcript = Transcript(
            engine: "parakeet",
            model: "test",
            created_at: "2026-07-31T00:00:00Z",
            attribution: "microphone=me and system=them are source tracks, not multi-speaker diarization",
            warnings: ["mic track ended with silent health"],
            segments: [segment("me", 0, 1_000, "Local transcript text")]
        )
        try transcript.write(to: directory)
        let markdown = try String(
            contentsOf: directory.appendingPathComponent("transcript.md"),
            encoding: .utf8
        )
        #expect(markdown.contains("not multi-speaker diarization"))
        #expect(markdown.contains("mic track ended with silent health"))
        #expect(markdown.contains("Local transcript text"))
        let decoded = try JSONDecoder().decode(
            Transcript.self,
            from: Data(contentsOf: directory.appendingPathComponent("transcript.json"))
        )
        #expect(decoded == transcript)
        #expect(mode(directory.appendingPathComponent("transcript.md")) == 0o600)
        #expect(mode(directory.appendingPathComponent("transcript.json")) == 0o600)
        #expect(mode(directory) == 0o700)
    }

    @Test("failed Markdown write leaves no JSON completion marker")
    func completionMarkerOrdering() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rwm-marker-\(UUID().uuidString)", isDirectory: true)
        try SecureStorage.createDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try SecureStorage.createDirectory(directory.appendingPathComponent("transcript.md"))
        let transcript = Transcript(
            engine: "parakeet",
            model: "test",
            created_at: "now",
            attribution: "tracks",
            warnings: [],
            segments: []
        )
        #expect(throws: (any Error).self) {
            try transcript.write(to: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("transcript.json").path))
    }

    private func segment(
        _ speaker: String,
        _ start: Int,
        _ end: Int,
        _ text: String
    ) -> Transcript.Segment {
        Transcript.Segment(
            speaker: speaker,
            start_ms: start,
            end_ms: end,
            text: text,
            suspected_echo: false,
            suppressed_as_echo: false,
            echo_match_confidence: nil
        )
    }

    private func mode(_ url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
