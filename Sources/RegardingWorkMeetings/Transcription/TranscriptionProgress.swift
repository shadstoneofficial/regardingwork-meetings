import AVFoundation
import Foundation

enum AudioAvailability: Sendable {
    case readable, missing, empty, unreadable

    static func inspect(_ url: URL) -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let file = try AVAudioFile(forReading: url)
            return file.length > 0 ? .readable : .empty
        } catch {
            return .unreadable
        }
    }
}

/// Private per-track checkpoints retain successful inference across retries.
/// Only a complete final transcript.json marks a session finished.
struct TranscriptionProgress: Codable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case pending, transcribed, noSpeech, failed, missing, emptyAudio, unreadable

        var succeeded: Bool { self == .transcribed || self == .noSpeech }
    }

    struct Track: Codable, Sendable {
        let source: SessionMeta.Track
        var outcome: Outcome = .pending
        var segments: [TranscriptSegment] = []
        var failure_class: String?
    }

    static let filename = "transcription-state.json"
    let schema_version: Int
    var state: String
    var engine: String?
    var model: String?
    var tracks: [Track]

    enum ProgressError: Error {
        case changedSources, incompatibleEngine, unsupportedSchema, unfinishedTracks
    }

    static func load(directory: URL, sources: [SessionMeta.Track]) throws -> Self {
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Self(schema_version: 1, state: "pending", tracks: sources.map { Track(source: $0) })
        }
        let progress = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard progress.schema_version == 1 else { throw ProgressError.unsupportedSchema }
        guard progress.tracks.map(\.source) == sources else { throw ProgressError.changedSources }
        return progress
    }

    func write(to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SecureStorage.write(try encoder.encode(self), to: directory.appendingPathComponent(Self.filename))
    }
}
