import Foundation
import Testing
@testable import RegardingWorkMeetings

@Suite("Configuration and identity")
struct ConfigTests {
    @Test("branded defaults and identifiers")
    func brandedDefaults() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        #expect(AppIdentity.bundleIdentifier == "com.regardingwork.meetings")
        #expect(AppIdentity.launchAgentIdentifier == "com.regardingwork.meetings")
        #expect(AppIdentity.executableName == "regardingwork-meetings")
        #expect(
            AppIdentity.recordingsRoot(home: home).path
                == "/Users/tester/RegardingWork Meetings"
        )
        #expect(
            AppIdentity.configurationURL(home: home).path
                == "/Users/tester/.config/regardingwork-meetings/config.json"
        )
    }

    @Test("configuration file loads local settings and argv hook")
    func loadsConfiguration() throws {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory
            .appendingPathComponent("rwm-config-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temporary) }
        let url = temporary.appendingPathComponent("config.json")
        try Data(
            """
            {
              "recordings_dir": "~/Private Meetings",
              "transcription": {"enabled": false, "engine": "parakeet"},
              "mic_voice_processing": true,
              "on_stop": ["~/bin/meeting-hook", "--local"]
            }
            """.utf8
        ).write(to: url)
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let config = ConfigLoader.load(from: url, home: home)
        #expect(config.recordingsDirectory?.path == "/Users/tester/Private Meetings")
        #expect(config.transcriptionEnabled == false)
        #expect(config.transcriptionEngine == "parakeet")
        #expect(config.micVoiceProcessing == true)
        #expect(config.onStop?.executable == "/Users/tester/bin/meeting-hook")
        #expect(config.onStop?.arguments == ["--local"])
    }

    @Test("CLI output directory takes precedence over config and default")
    func rootPrecedence() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let configured = URL(fileURLWithPath: "/configured", isDirectory: true)
        let config = AppConfig(recordingsDirectory: configured)
        #expect(
            ConfigLoader.resolveRoot(cliOverride: "/cli", config: config, home: home).path
                == "/cli"
        )
        #expect(
            ConfigLoader.resolveRoot(cliOverride: nil, config: config, home: home).path
                == "/configured"
        )
        #expect(
            ConfigLoader.resolveRoot(cliOverride: nil, config: AppConfig(), home: home).path
                == "/Users/tester/RegardingWork Meetings"
        )
    }

    @Test("default storage discovers the legacy root without changing custom roots")
    func legacyDiscovery() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        #expect(
            AppIdentity.recordingRootsForDiscovery(
                currentRoot: AppIdentity.recordingsRoot(home: home),
                home: home
            ).map(\.path)
                == [
                    "/Users/tester/RegardingWork Meetings",
                    "/Users/tester/RegardingWork/Meetings",
                ]
        )
        #expect(
            AppIdentity.recordingRootsForDiscovery(
                currentRoot: URL(fileURLWithPath: "/Volumes/Private/Meetings"),
                home: home
            ).map(\.path)
                == ["/Volumes/Private/Meetings"]
        )
    }

    @Test("hook uses argv without shell interpolation and appends one session argument")
    func safeHookArguments() {
        let command = HookCommand(
            executable: "/usr/local/bin/index-meeting",
            arguments: ["--label", "team; echo unsafe"]
        )
        let invocation = command.invocation(
            sessionDirectory: URL(fileURLWithPath: "/tmp/session with spaces")
        )
        #expect(invocation.executable == "/usr/local/bin/index-meeting")
        #expect(
            invocation.arguments
                == ["--label", "team; echo unsafe", "/tmp/session with spaces"]
        )
    }

    @Test("relative hook executable is disabled")
    func relativeHookIsDisabled() throws {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory
            .appendingPathComponent("rwm-hook-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temporary) }
        let url = temporary.appendingPathComponent("config.json")
        try Data(#"{"on_stop":["relative-hook","--unsafe"]}"#.utf8).write(to: url)
        let config = ConfigLoader.load(
            from: url,
            home: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        )
        #expect(config.onStop == nil)
    }
}
