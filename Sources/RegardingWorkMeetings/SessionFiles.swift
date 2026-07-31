import Foundation

struct RecordingManifest: Codable, Equatable, Sendable {
    let schema_version: Int
    let state: String
    let session_id: String
    let owner_pid: Int32
    let started_at: String
    let files: [String: String]
    var first_buffer_at: [String: String]
    var track_health: [String: TrackHealth]
}

struct SessionMetadata: Codable, Equatable, Sendable {
    let schema_version: Int
    let session_id: String
    let started: String
    let ended: String
    let duration_seconds: Int
    let files: [String: String]
    let start_offset_ms: [String: Int]
    let track_health: [String: TrackHealth]
    let recovered: Bool
    let recovery_note: String?
    let attribution: String
}

enum SessionFileWriter {
    static let manifestName = "recording.json"
    static let recoveredManifestName = "recording.recovered.json"
    static let metadataName = "meta.json"

    static func writeManifest(_ manifest: RecordingManifest, to directory: URL) throws {
        try SecureStorage.write(
            try encoded(manifest),
            to: directory.appendingPathComponent(manifestName)
        )
    }

    static func writeMetadata(_ metadata: SessionMetadata, to directory: URL) throws {
        try SecureStorage.write(
            try encoded(metadata),
            to: directory.appendingPathComponent(metadataName)
        )
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}
