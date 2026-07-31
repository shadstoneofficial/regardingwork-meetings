import AVFoundation
import Darwin
import Foundation

struct RecoveryReport: Equatable, Sendable {
    var recovered: [String] = []
    var deferred: [String] = []
    var warnings: [String] = []
}

enum SessionRecovery {
    typealias ProcessIsAlive = @Sendable (Int32) -> Bool
    typealias AudioIsReadable = @Sendable (URL) -> Bool

    static func discover(
        root: URL,
        now: Date = Date(),
        processIsAlive: ProcessIsAlive = defaultProcessIsAlive,
        audioIsReadable: AudioIsReadable = defaultAudioIsReadable
    ) -> RecoveryReport {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return RecoveryReport() }

        var report = RecoveryReport()
        for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let manifestURL = directory.appendingPathComponent(SessionFileWriter.manifestName)
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
            let metadataURL = directory.appendingPathComponent(SessionFileWriter.metadataName)
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                report.warnings.append(
                    "\(directory.lastPathComponent): completed metadata exists; left stale manifest untouched"
                )
                continue
            }
            guard
                let data = try? Data(contentsOf: manifestURL),
                let manifest = try? JSONDecoder().decode(RecordingManifest.self, from: data)
            else {
                report.warnings.append(
                    "\(directory.lastPathComponent): in-progress manifest is unreadable"
                )
                continue
            }
            if processIsAlive(manifest.owner_pid) {
                report.deferred.append(directory.lastPathComponent)
                continue
            }

            var files: [String: String] = [:]
            var health: [String: TrackHealth] = [:]
            for (track, filename) in manifest.files {
                let audio = directory.appendingPathComponent(filename)
                if audioIsReadable(audio) {
                    files[track] = filename
                    health[track] = TrackHealth(
                        state: .recovered,
                        detail: "readable audio recovered after an interrupted session"
                    )
                    try? SecureStorage.protectFile(audio)
                } else {
                    health[track] = TrackHealth(
                        state: .missing,
                        detail: "track was missing, empty, or unreadable during recovery"
                    )
                }
            }
            guard !files.isEmpty else {
                report.warnings.append(
                    "\(directory.lastPathComponent): no readable track; preserved for manual inspection"
                )
                continue
            }

            let iso = ISO8601DateFormatter()
            let started = iso.date(from: manifest.started_at) ?? now
            let metadata = SessionMetadata(
                schema_version: 1,
                session_id: manifest.session_id,
                started: manifest.started_at,
                ended: iso.string(from: now),
                duration_seconds: max(0, Int(now.timeIntervalSince(started))),
                files: files,
                start_offset_ms: recoveredOffsets(manifest: manifest, iso: iso),
                track_health: health,
                recovered: true,
                recovery_note: "Recovered conservatively from recording.json after its owner process exited.",
                attribution: "two-track source attribution (microphone=me, system=them), not speaker diarization"
            )
            do {
                try SessionFileWriter.writeMetadata(metadata, to: directory)
                let preserved = directory.appendingPathComponent(
                    SessionFileWriter.recoveredManifestName
                )
                try FileManager.default.moveItem(at: manifestURL, to: preserved)
                try SecureStorage.protectFile(preserved)
                report.recovered.append(directory.lastPathComponent)
            } catch {
                report.warnings.append(
                    "\(directory.lastPathComponent): recovery write failed: \(error)"
                )
            }
        }
        return report
    }

    private static func recoveredOffsets(
        manifest: RecordingManifest,
        iso: ISO8601DateFormatter
    ) -> [String: Int] {
        let dates = manifest.first_buffer_at.compactMapValues(iso.date(from:))
        guard let earliest = dates.values.min() else { return [:] }
        return dates.mapValues { max(0, Int($0.timeIntervalSince(earliest) * 1000)) }
    }

    private static func defaultProcessIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func defaultAudioIsReadable(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            let file = try AVAudioFile(forReading: url)
            return file.length > 0
        } catch {
            return false
        }
    }
}
