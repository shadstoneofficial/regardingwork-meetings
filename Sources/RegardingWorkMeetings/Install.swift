import ArgumentParser
import Foundation

/// Manage RegardingWork Meetings' LaunchAgent so it starts at login.
///
/// A LaunchAgent remains useful for source/CLI installations. Distribution
/// builds are a proper app bundle so macOS permissions have a stable identity.
struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install or remove the launch-at-login LaunchAgent."
    )

    @Flag(name: .long, help: "Register RegardingWork Meetings to start at login.")
    var launchAtLogin: Bool = false

    @Flag(name: .long, help: "Remove the launch-at-login agent.")
    var uninstall: Bool = false

    func run() throws {
        if launchAtLogin == uninstall {
            FileHandle.standardError.write(Data(
                "specify exactly one of --launch-at-login or --uninstall\n".utf8
            ))
            throw ExitCode(64)
        }

        if uninstall {
            try removeAgent()
        } else {
            try writeAgent()
        }
    }

    // MARK: -

    static let label = AppIdentity.launchAgentIdentifier

    private var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist")
    }

    private func writeAgent() throws {
        let binary = try resolveBinaryPath()
        let logs = AppIdentity.applicationSupportDirectory()
            .appendingPathComponent("Logs", isDirectory: true)
        try SecureStorage.createDirectory(logs)
        let stdout = logs.appendingPathComponent("stdout.log")
        let stderr = logs.appendingPathComponent("stderr.log")
        if !FileManager.default.fileExists(atPath: stdout.path) {
            try SecureStorage.write(Data(), to: stdout)
        }
        if !FileManager.default.fileExists(atPath: stderr.path) {
            try SecureStorage.write(Data(), to: stderr)
        }

        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [binary, "run"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false] as [String: Any],
            "ProcessType": "Interactive",
            "StandardOutPath": stdout.path,
            "StandardErrorPath": stderr.path,
        ]

        let url = plistURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try SecureStorage.write(data, to: url)

        // Best-effort bootstrap; ignore failure if already loaded.
        _ = runLaunchctl(["bootout", "gui/\(uid())", url.path])
        let result = runLaunchctl(["bootstrap", "gui/\(uid())", url.path])
        if result.status != 0 {
            FileHandle.standardError.write(Data(
                "warning: launchctl bootstrap exited \(result.status):\n\(result.stderr)\n".utf8
            ))
        }

        print("✓ launch-at-login installed")
        print("  plist:  \(url.path)")
        print("  binary: \(binary)")
        print("  logs:   \(stdout.path), \(stderr.path)")
    }

    private func removeAgent() throws {
        let url = plistURL
        if FileManager.default.fileExists(atPath: url.path) {
            _ = runLaunchctl(["bootout", "gui/\(uid())", url.path])
            try FileManager.default.removeItem(at: url)
            print("✓ launch-at-login removed")
        } else {
            print("nothing to remove (no agent at \(url.path))")
        }
    }

    private func resolveBinaryPath() throws -> String {
        let candidates = [
            "/Applications/\(AppIdentity.productName).app/Contents/MacOS/\(AppIdentity.executableName)",
            "/usr/local/bin/\(AppIdentity.executableName)",
        ]
        if let candidate = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) {
            return candidate
        }
        // Fall back to the running executable's resolved path.
        let argv0 = CommandLine.arguments.first ?? AppIdentity.executableName
        if argv0.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: argv0) {
            FileHandle.standardError.write(Data(
                "note: installed app/CLI not found; using \(argv0)\n".utf8
            ))
            return argv0
        }
        FileHandle.standardError.write(Data(
            "couldn't locate \(AppIdentity.executableName). Install the app in /Applications or the CLI in /usr/local/bin.\n".utf8
        ))
        throw ExitCode(1)
    }

    private func uid() -> uid_t { getuid() }

    private func runLaunchctl(_ args: [String]) -> (status: Int32, stderr: String) {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = args
        let errPipe = Pipe()
        task.standardError = errPipe
        task.standardOutput = Pipe()
        do {
            try task.run()
        } catch {
            return (-1, "\(error)")
        }
        task.waitUntilExit()
        let err = String(
            data: errPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (task.terminationStatus, err)
    }
}
