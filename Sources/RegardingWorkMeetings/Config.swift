import Foundation

struct HookCommand: Equatable, Sendable {
    let executable: String
    let arguments: [String]

    func invocation(sessionDirectory: URL) -> (executable: String, arguments: [String]) {
        (executable, arguments + [sessionDirectory.path])
    }
}

struct AppConfig: Equatable, Sendable {
    var recordingsDirectory: URL?
    var transcriptionEnabled = true
    var transcriptionEngine = "parakeet"
    var micVoiceProcessing = false
    var onStop: HookCommand?
}

enum ConfigLoader {
    static func load(from url: URL, home: URL) -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppConfig() }
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            warn("warning: \(url.path) is not valid JSON — ignoring config")
            return AppConfig()
        }

        var config = AppConfig()
        if let raw = json["recordings_dir"] as? String, !raw.isEmpty {
            config.recordingsDirectory = expand(raw, home: home)
        }
        if let transcription = json["transcription"] as? [String: Any] {
            config.transcriptionEnabled = transcription["enabled"] as? Bool ?? true
            config.transcriptionEngine = transcription["engine"] as? String ?? "parakeet"
        }
        config.micVoiceProcessing = json["mic_voice_processing"] as? Bool ?? false
        config.onStop = parseHook(json["on_stop"], home: home, source: url)
        return config
    }

    static func resolveRoot(
        cliOverride: String?,
        config: AppConfig,
        home: URL
    ) -> URL {
        if let cliOverride {
            return expand(cliOverride, home: home)
        }
        return config.recordingsDirectory ?? AppIdentity.recordingsRoot(home: home)
    }

    private static func parseHook(_ value: Any?, home: URL, source: URL) -> HookCommand? {
        guard let value else { return nil }
        guard
            let parts = value as? [String],
            let executable = parts.first,
            !executable.isEmpty
        else {
            warn(
                "warning: \(source.path) on_stop must be an argument array; "
                    + "shell strings are disabled"
            )
            return nil
        }
        let expanded = expandPath(executable, home: home)
        guard expanded.hasPrefix("/") else {
            warn("warning: \(source.path) on_stop executable must be an absolute path")
            return nil
        }
        return HookCommand(executable: expanded, arguments: Array(parts.dropFirst()))
    }

    private static func expand(_ path: String, home: URL) -> URL {
        URL(fileURLWithPath: expandPath(path, home: home), isDirectory: true)
    }

    private static func expandPath(_ path: String, home: URL) -> String {
        if path == "~" { return home.path }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}

enum Config {
    private static var current: AppConfig {
        ConfigLoader.load(
            from: AppIdentity.configurationURL(),
            home: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static var path: URL { AppIdentity.configurationURL() }
    static func recordingsDir() -> URL? { current.recordingsDirectory }
    static func onStop() -> HookCommand? { current.onStop }
    static func transcriptionEnabled() -> Bool { current.transcriptionEnabled }
    static func transcriptionEngine() -> String { current.transcriptionEngine }
    static func micVoiceProcessing() -> Bool { current.micVoiceProcessing }

    static func resolveRoot(cliOverride: String?) -> URL {
        ConfigLoader.resolveRoot(
            cliOverride: cliOverride,
            config: current,
            home: FileManager.default.homeDirectoryForCurrentUser
        )
    }
}
