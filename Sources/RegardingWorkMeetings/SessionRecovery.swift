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
    typealias AudioDuration = @Sendable (URL) -> TimeInterval?

    static func discover(
        root: URL,
        now: Date = Date(),
        processIsAlive: ProcessIsAlive = defaultProcessIsAlive,
        audioIsReadable: AudioIsReadable = defaultAudioIsReadable,
        audioDuration: AudioDuration = defaultAudioDuration
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

            let preserved = directory.appendingPathComponent(SessionFileWriter.recoveredManifestName)
            guard !FileManager.default.fileExists(atPath: preserved.path) else {
                report.warnings.append("\(directory.lastPathComponent): existing recovery evidence left untouched")
                continue
            }
            var systemSegments = manifest.system_audio_segments
            let segmentNames = (systemSegments ?? []).map(\.file)
            guard manifest.files.values.allSatisfy(SessionMeta.validFilename),
                  segmentNames.allSatisfy(SessionMeta.validFilename),
                  Set(segmentNames).count == segmentNames.count,
                  !segmentNames.contains(manifest.files["mic"] ?? ""),
                  (systemSegments ?? []).allSatisfy({ $0.offset_ms >= 0 }) else {
                report.warnings.append("\(directory.lastPathComponent): invalid audio filename; preserved for inspection")
                continue
            }
            var readableTracks = 0
            var health: [String: TrackHealth] = [:]
            let iso = ISO8601DateFormatter()
            let started = iso.date(from: manifest.started_at) ?? now
            var endpoints = (manifest.last_buffer_at ?? [:]).values.compactMap(iso.date(from:))
            let origin = (manifest.first_buffer_at.values.compactMap(iso.date(from:))
                + (systemSegments ?? []).compactMap { $0.first_buffer_at.flatMap(iso.date(from:)) }).min() ?? started
            var sources = manifest.files.map { (track: $0.key, filename: $0.value, index: Optional<Int>.none) }
            if let segments = systemSegments, !segments.isEmpty {
                sources.removeAll { $0.track == "system" }
                sources += segments.enumerated().map { (track: "system", filename: $0.element.file, index: Optional($0.offset)) }
            }
            for source in sources {
                let (track, filename, index) = source
                let audio = directory.appendingPathComponent(filename)
                var first = manifest.first_buffer_at[track].flatMap(iso.date(from:)) ?? started
                if let index, let segment = systemSegments?[index] {
                    first = segment.first_buffer_at.flatMap(iso.date(from:))
                        ?? iso.date(from: segment.started_at) ?? started
                }
                if audioIsReadable(audio) {
                    readableTracks += 1
                    let previous = manifest.track_health[track]
                    if health[track] == nil {
                        health[track] = previous?.needsAttention == true ? previous : TrackHealth(
                            state: .recovered, detail: "readable audio recovered; completeness and audibility require inspection"
                        )
                    }
                    if let index { systemSegments?[index].capture_started = true }
                    if let duration = audioDuration(audio), duration.isFinite, duration >= 0 {
                        endpoints.append(first.addingTimeInterval(duration))
                    }
                    try? SecureStorage.protectFile(audio)
                } else {
                    health[track] = manifest.track_health[track]?.needsAttention == true
                        ? manifest.track_health[track] : TrackHealth(
                        state: .missing,
                        detail: "track was missing, empty, or unreadable during recovery"
                    )
                }
                if let index {
                    systemSegments?[index].offset_ms = max(0, Int(first.timeIntervalSince(origin) * 1000))
                }
            }
            guard readableTracks > 0 else {
                report.warnings.append(
                    "\(directory.lastPathComponent): no readable track; preserved for manual inspection"
                )
                continue
            }

            // Capture evidence, not the next launch's time or microphone, owns this history.
            let ended = max(started, endpoints.filter { $0 >= started && $0 <= now }.max() ?? started)
            let metadata = SessionMetadata(
                schema_version: 1,
                session_id: manifest.session_id,
                started: manifest.started_at,
                ended: iso.string(from: ended),
                duration_seconds: max(0, Int(ended.timeIntervalSince(started))),
                files: manifest.files,
                start_offset_ms: recoveredOffsets(manifest: manifest, iso: iso),
                track_health: health,
                recovered: true,
                recovery_note: "Recovered from recording.json; end derived from persisted buffers/readable audio, not relaunch. "
                    + "Historical track health retained; unreadable tracks remain retryable. "
                    + (endpoints.isEmpty ? "Capture duration unavailable; recorded as zero, not invented. " : "")
                    + (manifest.preserved_zero_filled_mic == nil ? "" : "A zero-filled microphone attempt was preserved."),
                attribution: "two-track source attribution (microphone=me, system=them), not speaker diarization",
                microphone_device_at_start: manifest.microphone_device,
                microphone_device_at_end: manifest.microphone_device_at_capture,
                microphone_recovery_attempted: manifest.microphone_recovery_attempted,
                microphone_configuration_restarts: manifest.microphone_configuration_restarts,
                preserved_zero_filled_mic: manifest.preserved_zero_filled_mic,
                microphone_route_history: manifest.microphone_route_history,
                track_health_history: manifest.track_health_history,
                system_audio_segments: systemSegments?.isEmpty == false ? systemSegments : nil,
                system_capture_interruptions: manifest.system_capture_interruptions,
                system_recovery_attempts: manifest.system_recovery_attempts,
                system_output_route_history: manifest.system_output_route_history,
                app_build: manifest.app_build,
                macos_version: manifest.macos_version,
                first_buffer_at: manifest.first_buffer_at,
                last_buffer_at: manifest.last_buffer_at
            )
            do {
                try SessionFileWriter.writeMetadata(metadata, to: directory)
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

    private static func defaultAudioDuration(_ url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
