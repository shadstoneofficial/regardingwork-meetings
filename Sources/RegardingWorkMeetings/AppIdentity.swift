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
            .appendingPathComponent("RegardingWork", isDirectory: true)
            .appendingPathComponent("Meetings", isDirectory: true)
    }

    static func applicationSupportDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(productName, isDirectory: true)
    }
}
