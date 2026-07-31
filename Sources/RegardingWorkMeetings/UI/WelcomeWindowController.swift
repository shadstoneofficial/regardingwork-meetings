import AppKit
import AVFoundation
import FluidAudio
import Foundation

enum OnboardingPreferences {
    static let showOnLaunchKey = "showWelcomeOnLaunch"
    static let recordingStartedKey = "hasStartedRecording"

    static func shouldShowOnLaunch(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: showOnLaunchKey) != nil else { return true }
        return defaults.bool(forKey: showOnLaunchKey)
    }

    static func setShowOnLaunch(_ value: Bool, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: showOnLaunchKey)
    }

    static func markRecordingStarted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: recordingStartedKey)
    }

    static func hasStartedRecording(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: recordingStartedKey)
    }
}

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let recordingsRoot: URL
    private let defaults: UserDefaults

    private let microphoneStatus = NSTextField(labelWithString: "")
    private let systemAudioStatus = NSTextField(labelWithString: "")
    private let modelStatus = NSTextField(labelWithString: "")
    private let microphoneButton = NSButton()
    private let modelButton = NSButton()
    private let recordingButton = NSButton()
    private let showOnLaunchCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    var onToggleRecording: (() -> Void)?
    var onOpenRecordings: (() -> Void)?
    var onClosed: (() -> Void)?

    init(recordingsRoot: URL, defaults: UserDefaults = .standard) {
        self.recordingsRoot = recordingsRoot
        self.defaults = defaults

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppIdentity.productName) — Welcome & Setup"
        window.minSize = NSSize(width: 640, height: 600)
        window.center()

        super.init(window: window)
        window.delegate = self
        let content = makeContent()
        content.preferredContentSize = NSSize(width: 720, height: 700)
        window.contentViewController = content
        window.setContentSize(NSSize(width: 720, height: 700))
        window.center()
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    func updateRecording(_ recording: Bool) {
        recordingButton.title = recording ? "Stop Test Recording" : "Start Test Recording"
        recordingButton.bezelColor = recording ? .systemRed : .controlAccentColor
    }

    func noteRecordingStarted() {
        OnboardingPreferences.markRecordingStarted(defaults: defaults)
        refresh()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }

    private func makeContent() -> NSViewController {
        let controller = NSViewController()
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 34, bottom: 30, right: 34)
        document.addSubview(stack)

        stack.addArrangedSubview(header())
        stack.addArrangedSubview(introText())
        stack.addArrangedSubview(section(
            number: "1",
            title: "Allow microphone access",
            body: "Records your voice and nearby room audio as the “me” track.",
            status: microphoneStatus,
            action: microphoneButton,
            actionTitle: "Request Microphone Access",
            selector: #selector(requestMicrophone)
        ))
        stack.addArrangedSubview(section(
            number: "2",
            title: "Allow Mac system audio",
            body: "Records everything this Mac plays as the “them” track—including meeting audio, notifications, and unrelated apps.",
            status: systemAudioStatus,
            action: NSButton(
                title: "Open System Audio Settings",
                target: self,
                action: #selector(openSystemAudioSettings)
            )
        ))
        stack.addArrangedSubview(section(
            number: "3",
            title: "Prepare on-device transcription",
            body: "Downloads Parakeet once, then transcription runs locally on this Mac. The current engine is English-only.",
            status: modelStatus,
            action: modelButton,
            actionTitle: "Prepare Model (~600 MB)",
            selector: #selector(prepareModel)
        ))
        stack.addArrangedSubview(storageSection())
        stack.addArrangedSubview(privacyNotice())
        stack.addArrangedSubview(footer())

        controller.view = NSView(
            frame: NSRect(x: 0, y: 0, width: 720, height: 700)
        )
        controller.view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: controller.view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        return controller
    }

    private func header() -> NSView {
        let image = NSImageView()
        image.image = NSApp.applicationIconImage
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 76),
            image.heightAnchor.constraint(equalToConstant: 76),
        ])

        let title = NSTextField(labelWithString: "Welcome to \(AppIdentity.productName)")
        title.font = .systemFont(ofSize: 28, weight: .bold)
        let family = NSTextField(labelWithString: AppIdentity.productFamily)
        family.font = .systemFont(ofSize: 13, weight: .semibold)
        family.textColor = .secondaryLabelColor
        let local = NSTextField(labelWithString: "PRIVATE · LOCAL · ON-DEVICE")
        local.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        local.textColor = .systemGreen

        let text = NSStackView(views: [family, title, local])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 5

        let row = NSStackView(views: [image, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        return row
    }

    private func introText() -> NSView {
        label(
            "Record your microphone and Mac audio as separate local tracks, then create "
                + "a transcript on this Mac. Complete these three setup steps, run a short "
                + "test, and use the waveform icon in the menu bar for future recordings.",
            size: 15,
            color: .labelColor
        )
    }

    private func section(
        number: String,
        title: String,
        body: String,
        status: NSTextField,
        action: NSButton,
        actionTitle: String? = nil,
        selector: Selector? = nil
    ) -> NSView {
        if let actionTitle { action.title = actionTitle }
        if let selector {
            action.target = self
            action.action = selector
        }
        action.bezelStyle = .rounded

        let badge = NSTextField(labelWithString: number)
        badge.alignment = .center
        badge.font = .systemFont(ofSize: 14, weight: .bold)
        badge.textColor = .white
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        badge.layer?.cornerRadius = 14
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 28),
            badge.heightAnchor.constraint(equalToConstant: 28),
        ])

        let heading = label(title, size: 16, weight: .semibold)
        let description = label(body, size: 13, color: .secondaryLabelColor)
        status.font = .systemFont(ofSize: 13, weight: .medium)
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 0

        let copy = NSStackView(views: [heading, description, status, action])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 7

        let row = NSStackView(views: [badge, copy])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 14
        return card(row)
    }

    private func storageSection() -> NSView {
        let heading = label("Your local recordings folder", size: 16, weight: .semibold)
        let path = label(recordingsRoot.path, size: 12, color: .secondaryLabelColor)
        path.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let button = NSButton(
            title: "Open Recordings Folder",
            target: self,
            action: #selector(openRecordings)
        )
        button.bezelStyle = .rounded
        let content = NSStackView(views: [heading, path, button])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 7
        return card(content)
    }

    private func privacyNotice() -> NSView {
        let heading = label("Before you record", size: 16, weight: .semibold)
        let copy = label(
            "System capture records everything the Mac plays—not only the meeting app. "
                + "Use headphones and Focus mode, close unrelated media, notify participants, "
                + "and obtain consent where required. Audio and transcripts stay local unless "
                + "you intentionally move or share them.",
            size: 13,
            color: .secondaryLabelColor
        )
        let content = NSStackView(views: [heading, copy])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 7
        return card(content, color: NSColor.systemOrange.withAlphaComponent(0.10))
    }

    private func footer() -> NSView {
        showOnLaunchCheckbox.title = "Show this window when \(AppIdentity.productName) opens"
        showOnLaunchCheckbox.state = OnboardingPreferences.shouldShowOnLaunch(defaults: defaults)
            ? .on
            : .off
        showOnLaunchCheckbox.target = self
        showOnLaunchCheckbox.action = #selector(showOnLaunchChanged)

        recordingButton.title = "Start Test Recording"
        recordingButton.bezelStyle = .rounded
        recordingButton.keyEquivalent = "\r"
        recordingButton.target = self
        recordingButton.action = #selector(toggleRecording)

        let continueButton = NSButton(
            title: "Continue in Menu Bar",
            target: self,
            action: #selector(closeWindow)
        )
        continueButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [continueButton, recordingButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let content = NSStackView(views: [showOnLaunchCheckbox, buttons])
        content.orientation = .vertical
        content.alignment = .trailing
        content.spacing = 14
        return content
    }

    private func card(_ content: NSView, color: NSColor = .controlBackgroundColor) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = color.cgColor
        container.layer?.cornerRadius = 12
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 0.5
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
        return container
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    private func refresh() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            setStatus(microphoneStatus, "Ready — microphone access allowed", color: .systemGreen)
            microphoneButton.title = "Microphone Allowed"
            microphoneButton.isEnabled = false
        case .notDetermined:
            setStatus(microphoneStatus, "Not requested yet", color: .systemOrange)
            microphoneButton.title = "Request Microphone Access"
            microphoneButton.isEnabled = true
        case .denied, .restricted:
            setStatus(
                microphoneStatus,
                "Needs attention — enable access in System Settings",
                color: .systemRed
            )
            microphoneButton.title = "Open Microphone Settings"
            microphoneButton.isEnabled = true
        @unknown default:
            setStatus(microphoneStatus, "Unknown permission state", color: .systemRed)
        }

        if OnboardingPreferences.hasStartedRecording(defaults: defaults) {
            setStatus(
                systemAudioStatus,
                "A recording has started on this Mac; confirm “system ✓” while audio plays",
                color: .systemOrange
            )
        } else {
            setStatus(
                systemAudioStatus,
                "macOS asks when you start your first recording; status cannot be checked in advance",
                color: .systemOrange
            )
        }

        guard Config.transcriptionEnabled() else {
            setStatus(modelStatus, "Transcription is disabled in config", color: .secondaryLabelColor)
            modelButton.isEnabled = false
            return
        }
        let cache = AsrModels.defaultCacheDirectory(for: .v2)
        if AsrModels.modelsExist(at: cache, version: .v2) {
            setStatus(modelStatus, "Ready — Parakeet model is stored locally", color: .systemGreen)
            modelButton.title = "Model Ready"
            modelButton.isEnabled = false
        } else {
            setStatus(modelStatus, "Not prepared — internet is needed once", color: .systemOrange)
            modelButton.title = "Prepare Model (~600 MB)"
            modelButton.isEnabled = true
        }
    }

    private func setStatus(_ field: NSTextField, _ text: String, color: NSColor) {
        field.stringValue = text
        field.textColor = color
    }

    @objc private func requestMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .denied || status == .restricted {
            openPrivacySettings(anchor: "Privacy_Microphone")
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    @objc private func openSystemAudioSettings() {
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    @objc private func prepareModel() {
        modelButton.isEnabled = false
        setStatus(modelStatus, "Preparing local model…", color: .systemBlue)
        Task { [weak self] in
            do {
                let engine = ParakeetEngine()
                try await engine.prepare()
                await engine.release()
                await MainActor.run {
                    guard let self else { return }
                    self.setStatus(
                        self.modelStatus,
                        "Ready — Parakeet model is stored locally",
                        color: .systemGreen
                    )
                    self.modelButton.title = "Model Ready"
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.setStatus(
                        self.modelStatus,
                        "Preparation failed — \(error)",
                        color: .systemRed
                    )
                    self.modelButton.isEnabled = true
                }
            }
        }
    }

    @objc private func openRecordings() {
        onOpenRecordings?()
    }

    @objc private func toggleRecording() {
        onToggleRecording?()
    }

    @objc private func showOnLaunchChanged() {
        OnboardingPreferences.setShowOnLaunch(
            showOnLaunchCheckbox.state == .on,
            defaults: defaults
        )
    }

    @objc private func closeWindow() {
        window?.performClose(nil)
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
