import Foundation

enum AppIdentity {
    static let productName = "RegardingWork Meetings"
    static let productFamily = "RegardingWork Voice"
    static let executableName = "regardingwork-meetings"
    static let bundleIdentifier = "com.regardingwork.meetings"
    static let launchAgentIdentifier = bundleIdentifier
    static let website = "https://regardingwork.com"

    static func configurationURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent(executableName, isDirectory: true)
            .appendingPathComponent("config.json")
    }

    static func recordingsRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(productName, isDirectory: true)
    }

    static func legacyRecordingsRoot(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home
            .appendingPathComponent("RegardingWork", isDirectory: true)
            .appendingPathComponent("Meetings", isDirectory: true)
    }

    /// Keep unfinished sessions from the former default discoverable without
    /// moving, renaming, overwriting, or deleting any user data. Explicit CLI
    /// and configuration overrides remain isolated to the selected root.
    static func recordingRootsForDiscovery(
        currentRoot: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let current = currentRoot.standardizedFileURL
        guard current.path == recordingsRoot(home: home).standardizedFileURL.path else {
            return [current]
        }
        let legacy = legacyRecordingsRoot(home: home).standardizedFileURL
        return legacy.path == current.path ? [current] : [current, legacy]
    }

    static func applicationSupportDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(productName, isDirectory: true)
    }
}
