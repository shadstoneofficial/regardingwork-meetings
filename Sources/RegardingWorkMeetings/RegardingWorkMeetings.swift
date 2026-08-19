import AppKit
import ArgumentParser
import Foundation

@main
struct RegardingWorkMeetings: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: AppIdentity.executableName,
        abstract: "\(AppIdentity.productName): local two-track meeting recording and on-device transcription.",
        subcommands: [Run.self, Doctor.self, Install.self],
        defaultSubcommand: Run.self
    )
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the menu-bar daemon (default)."
    )

    @Option(name: .long, help: "Recordings root directory (overrides the config file).")
    var out: String?

    func run() throws {
        // ArgumentParser invokes run() on the main thread; promote that fact
        // to the type system so AppKit calls are cleanly isolated.
        try MainActor.assumeIsolated { try runMain() }
    }

    @MainActor
    private func runMain() throws {
        let root = Config.resolveRoot(cliOverride: out)

        // Keep the app available so Welcome & Setup can explain and repair
        // denied permissions or an unavailable recordings folder.
        let checks = DoctorReport.run(recordingsRoot: root)
        if !DoctorReport.allOK(checks) {
            FileHandle.standardError.write(Data("startup checks need attention:\n".utf8))
            DoctorReport.print(checks)
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let appDelegate = MeetingsApplicationDelegate()
        app.delegate = appDelegate
        let controller = AppController(root: root)
        appDelegate.onReopen = { [weak controller] in controller?.showSetup() }

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            FileHandle.standardError.write(Data("\nshutting down\n".utf8))
            MainActor.assumeIsolated { controller.shutdown() }
        }
        sigint.resume()
        signal(SIGINT, SIG_IGN)

        FileHandle.standardError.write(Data(
            "\(AppIdentity.productName) ready · recordings → \(root.path) · ^C to quit\n".utf8
        ))
        app.run()
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check microphone, system audio, and recordings folder."
    )

    func run() throws {
        let checks = DoctorReport.run(recordingsRoot: Config.resolveRoot(cliOverride: nil))
        DoctorReport.print(checks)
        if !DoctorReport.allOK(checks) {
            throw ExitCode(1)
        }
    }
}

/// Owns the menu bar, the current recording session, and the elapsed-time
/// ticker. All state transitions happen on the main actor.
@MainActor
final class AppController {
    private let root: URL
    private let menuBar = MenuBarController()
    private let transcription = TranscriptionCoordinator()
    private var session: RecordingSession?
    private var ticker: Timer?
    private var lastHealth: [String: TrackHealthState] = [:]
    private var welcome: WelcomeWindowController?

    init(root: URL) {
        self.root = root
        menuBar.onToggle = { [weak self] in self?.toggle() }
        menuBar.onShowSetup = { [weak self] in self?.showSetup() }
        menuBar.onOpenFolder = { [weak self] in self?.openFolder() }
        menuBar.onRetryTranscriptions = { [weak self] in self?.retryTranscriptions() }
        menuBar.onQuit = { [weak self] in self?.shutdown() }
        menuBar.update(recording: false, elapsed: nil)

        let welcome = WelcomeWindowController(recordingsRoot: root)
        welcome.onToggleRecording = { [weak self] in self?.toggle() }
        welcome.onOpenRecordings = { [weak self] in self?.openFolder() }
        welcome.onClosed = {
            NSApp.setActivationPolicy(.accessory)
        }
        self.welcome = welcome
        if OnboardingPreferences.shouldShowOnLaunch() {
            DispatchQueue.main.async { [weak self] in self?.showSetup() }
        }

        let discoveryRoots = AppIdentity.recordingRootsForDiscovery(currentRoot: root)
        let recoveryReports = discoveryRoots.map { discoveryRoot in
            (root: discoveryRoot, report: SessionRecovery.discover(root: discoveryRoot))
        }
        let recovered = recoveryReports.flatMap(\.report.recovered)
        let recoveryWarnings = recoveryReports.flatMap { entry in
            entry.report.warnings.map { "\(entry.root.path): \($0)" }
        }
        if !recovered.isEmpty {
            menuBar.updateRecovery(
                "recovered \(recovered.count) interrupted session(s)"
            )
            notifyUser(
                title: "\(AppIdentity.productName) — recovery complete",
                body: "Recovered: \(recovered.joined(separator: ", "))"
            )
        } else if !recoveryWarnings.isEmpty {
            menuBar.updateRecovery("recovery needs attention")
        }
        for warning in recoveryWarnings {
            FileHandle.standardError.write(Data("recovery warning: \(warning)\n".utf8))
        }

        Task { [transcription, discoveryRoots] in
            await transcription.setStatusHandler { status in
                Task { @MainActor [weak self] in
                    self?.showTranscription(status)
                }
            }
            for discoveryRoot in discoveryRoots {
                await transcription.resumePending(root: discoveryRoot)
            }
        }
    }

    /// Stop any live session cleanly (finalizing files) and exit.
    func shutdown() {
        stopSession()
        NSApp.terminate(nil)
    }

    private func toggle() {
        if session == nil {
            startSession()
        } else {
            stopSession()
        }
    }

    private func startSession() {
        do {
            let newSession = try RecordingSession(root: root)
            try newSession.start()
            session = newSession
            lastHealth = [:]
            FileHandle.standardError.write(Data("● recording → \(newSession.dir.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("recording start failed: \(error)\n".utf8))
            notifyUser(title: "\(AppIdentity.productName) — recording failed", body: "\(error)")
            return
        }

        menuBar.update(recording: true, elapsed: "0:00")
        welcome?.noteRecordingStarted()
        welcome?.updateRecording(true)
        updateHealth()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopSession() {
        guard let session else { return }
        session.stop()
        let elapsed = Self.format(Date().timeIntervalSince(session.startedAt))
        FileHandle.standardError.write(Data(
            "○ stopped · \(elapsed) · \(session.dir.path)\n".utf8
        ))
        self.session = nil
        lastHealth = [:]
        ticker?.invalidate()
        ticker = nil
        menuBar.update(recording: false, elapsed: nil)
        welcome?.updateRecording(false)

        let dir = session.dir
        Task { [transcription] in await transcription.enqueue(dir) }
    }

    private func showTranscription(_ status: TranscriptionCoordinator.Status) {
        switch status {
        case .idle:
            menuBar.updateTranscription(nil)
        case .transcribing(let name, let queued):
            menuBar.updateTranscription(
                queued > 0 ? "transcribing \(name) · \(queued) queued" : "transcribing \(name)"
            )
        case .failed(let name):
            menuBar.updateTranscription("transcription failed · \(name)", failed: true)
        }
    }

    private func tick() {
        guard let session else { return }
        menuBar.update(
            recording: true,
            elapsed: Self.format(Date().timeIntervalSince(session.startedAt))
        )
        updateHealth()
    }

    private func updateHealth() {
        guard let session else { return }
        let health = session.health()
        menuBar.updateHealth(health)
        for track in ["mic", "system"] {
            guard let current = health[track] else { continue }
            let previous = lastHealth[track]
            if current.needsAttention, previous != current.state {
                notifyUser(
                    title: "\(AppIdentity.productName) — \(track) \(current.state.rawValue)",
                    body: "\(current.detail). The recording may be incomplete."
                )
            }
            lastHealth[track] = current.state
        }
    }

    private func openFolder() {
        try? SecureStorage.createDirectory(root)
        NSWorkspace.shared.open(root)
    }

    private func retryTranscriptions() {
        let roots = AppIdentity.recordingRootsForDiscovery(currentRoot: root)
        Task { [transcription, weak self] in
            let count = await transcription.retryPending(roots: roots)
            await MainActor.run {
                guard let self else { return }
                self.menuBar.finishRetryRequest(found: count)
                if count == 0 {
                    notifyUser(
                        title: "\(AppIdentity.productName) — nothing to retry",
                        body: "No unfinished sessions were found. Completed transcripts were left unchanged."
                    )
                }
            }
        }
    }

    func showSetup() {
        welcome?.showWindow(nil)
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
