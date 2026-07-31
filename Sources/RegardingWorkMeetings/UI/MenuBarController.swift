import AppKit

/// Status bar item in the top-right of the menu bar. Shows recording state at
/// a glance and keeps recording controls available after the setup window is
/// closed.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let stateLabel: NSMenuItem
    private let healthLabel: NSMenuItem
    private let recoveryLabel: NSMenuItem
    private let transcriptionLabel: NSMenuItem
    private let toggleItem: NSMenuItem

    var onToggle: (() -> Void)?
    var onShowSetup: (() -> Void)?
    var onOpenFolder: (() -> Void)?
    var onQuit: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.autoenablesItems = false

        stateLabel = NSMenuItem(title: "idle", action: nil, keyEquivalent: "")
        stateLabel.isEnabled = false
        menu.addItem(stateLabel)

        healthLabel = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        healthLabel.isEnabled = false
        healthLabel.isHidden = true
        menu.addItem(healthLabel)

        recoveryLabel = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        recoveryLabel.isEnabled = false
        recoveryLabel.isHidden = true
        menu.addItem(recoveryLabel)

        transcriptionLabel = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        transcriptionLabel.isEnabled = false
        transcriptionLabel.isHidden = true
        menu.addItem(transcriptionLabel)

        menu.addItem(.separator())

        let setup = NSMenuItem(
            title: "Welcome & Setup…",
            action: #selector(showSetupClicked),
            keyEquivalent: ","
        )
        menu.addItem(setup)

        toggleItem = NSMenuItem(
            title: "Start recording",
            action: #selector(toggleClicked),
            keyEquivalent: "r"
        )
        menu.addItem(toggleItem)

        let openFolder = NSMenuItem(
            title: "Open recordings folder",
            action: #selector(openFolderClicked),
            keyEquivalent: "o"
        )
        menu.addItem(openFolder)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit \(AppIdentity.productName)",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        for item in [setup, toggleItem, openFolder, quit] {
            item.target = self
        }

        statusItem.menu = menu

        if let button = statusItem.button {
            let image = Self.regardingWorkImage()
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeft
            button.toolTip = AppIdentity.productName
            button.setAccessibilityLabel(AppIdentity.productName)
        }
    }

    /// Reflect recording state in the icon tint and menu item titles. The
    /// menu bar shows only the feather (red while recording); the elapsed
    /// counter lives in the menu's state label. Call once a second while
    /// recording.
    func update(recording: Bool, elapsed: String?) {
        stateLabel.title = recording ? "● recording · \(elapsed ?? "0:00")" : "idle"
        toggleItem.title = recording ? "Stop recording" : "Start recording"
        if !recording { healthLabel.isHidden = true }
        if recording {
            let configuration = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            statusItem.button?.image = NSImage(
                systemSymbolName: "record.circle.fill",
                accessibilityDescription: "Recording"
            )?.withSymbolConfiguration(configuration)
            statusItem.button?.image?.isTemplate = false
        } else {
            statusItem.button?.image = Self.regardingWorkImage()
            statusItem.button?.image?.isTemplate = true
        }
    }

    func updateHealth(_ health: [String: TrackHealth]) {
        guard let mic = health["mic"], let system = health["system"] else {
            healthLabel.isHidden = true
            return
        }
        healthLabel.title = "mic \(mic.menuText) · system \(system.menuText)"
        healthLabel.isHidden = false
    }

    func updateRecovery(_ text: String?) {
        recoveryLabel.title = text.map { "recovery: \($0)" } ?? ""
        recoveryLabel.isHidden = text == nil
    }

    /// Show transcription progress/failure as a second status line in the
    /// menu; nil hides it. Independent of recording state — a new recording
    /// can run while the last one transcribes.
    func updateTranscription(_ text: String?) {
        transcriptionLabel.title = text ?? ""
        transcriptionLabel.isHidden = text == nil
    }

    // Code-native monochrome monogram. This intentionally differs from the
    // waveform used by RegardingWork Dictate so both apps remain recognizable
    // when they are running together.
    private static let regardingWorkSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="26" height="18"
    viewBox="0 0 26 18" fill="none" stroke="currentColor" stroke-width="1.7"
    stroke-linecap="round" stroke-linejoin="round">
    <path d="M2.5 15V3.5h4.2c2.5 0 4 1.3 4 3.4s-1.5 3.4-4 3.4H2.5
    M7 10.3 11 15
    M13 3.5 15.2 15l3.1-7.5 3.1 7.5 2.1-11.5"/>
    </svg>
    """

    private static func regardingWorkImage() -> NSImage? {
        guard let data = regardingWorkSVG.data(using: .utf8),
              let image = NSImage(data: data)
        else { return nil }
        image.size = NSSize(width: 24, height: 16)
        return image
    }

    @objc private func toggleClicked() { onToggle?() }
    @objc private func showSetupClicked() { onShowSetup?() }
    @objc private func openFolderClicked() { onOpenFolder?() }
    @objc private func quitClicked() { onQuit?() }
}
