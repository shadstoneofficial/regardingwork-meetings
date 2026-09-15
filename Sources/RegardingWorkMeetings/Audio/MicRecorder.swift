import AVFoundation
import Foundation
import os.lock

private final class ConverterInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var supplied = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

/// Records the default input device to a file via AVAudioEngine, encoding AAC
/// mono. Buffers stream straight to disk — nothing is held in memory, so
/// session length is unbounded.
///
/// With voice processing on (opt-in), Apple's echo canceller subtracts
/// speaker playback from the mic so the system track doesn't bleed into the
/// mic track. VoiceProcessingIO is a duplex unit, not an input effect: it
/// needs a rendered output path and one explicit mono client format on both
/// sides, or it silently delivers zeroed buffers (rca-001). The shared digital
/// liveness check catches that condition in both voice-processed and raw input.
final class MicRecorder: @unchecked Sendable {
    enum RecorderError: Error, CustomStringConvertible {
        case engineStartFailed(Error)
        case fileCreationFailed(Error)
        case formatUnsupported(AVAudioFormat)
        case missingExistingFile

        var description: String {
            switch self {
            case .engineStartFailed(let e): return "mic engine start failed: \(e)"
            case .fileCreationFailed(let e): return "mic file creation failed: \(e)"
            case .formatUnsupported(let f): return "can't downmix mic format \(f)"
            case .missingExistingFile: return "mic restart could not find the open recording file"
            }
        }
    }

    private var engine = AVAudioEngine()
    private var url: URL?
    private(set) var isRecording = false
    private(set) var deviceAtStart: AudioInputDeviceIdentity?
    private var configurationObserver: NSObjectProtocol?
    private var configurationRestartPending = false

    private struct LockedState {
        var file: AVAudioFile?
        var firstBufferAt: Date?
        var lastBufferAt: Date?
        var lastSignalAt: Date?
        var lastNonzeroAt: Date?
        var zeroFilledSince: Date?
        var digitalSilenceRecoveryAttempted = false
        var digitalSilenceRecoveryScheduled = false
        var configurationRestartCount = 0
        var preservedZeroFile: String?
        var failure: String?
    }
    private let state = OSAllocatedUnfairLock(initialState: LockedState())

    var firstBufferAt: Date? { state.withLock { $0.firstBufferAt } }

    func snapshot() -> RecorderSnapshot {
        let recording = isRecording
        return state.withLock {
            RecorderSnapshot(
                isRecording: recording,
                firstBufferAt: $0.firstBufferAt,
                lastBufferAt: $0.lastBufferAt,
                lastSignalAt: $0.lastSignalAt,
                lastNonzeroAt: $0.lastNonzeroAt,
                zeroFilledSince: $0.zeroFilledSince,
                failure: $0.failure
            )
        }
    }

    var digitalSilenceRecoveryAttempted: Bool {
        state.withLock { $0.digitalSilenceRecoveryAttempted }
    }

    var preservedZeroFile: String? { state.withLock { $0.preservedZeroFile } }
    var configurationRestartCount: Int { state.withLock { $0.configurationRestartCount } }

    /// Start capturing the mic, encoding AAC into `url` (use a .caf extension
    /// — CAF needs no finalization pass, so a crash loses nothing written).
    func start(writingTo url: URL) throws {
        guard !isRecording else { return }
        self.url = url
        deviceAtStart = DefaultAudioInputDevice.current()
        try attach(voiceProcessing: Config.micVoiceProcessing())
        isRecording = true
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, (notification.object as? AVAudioEngine) === self.engine else { return }
            self.handleConfigurationChange()
        }
    }

    /// Stop capturing and finalize the file. Idempotent.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        configurationRestartPending = false
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        state.withLock { $0.file = nil }
        if let url { try? SecureStorage.protectFile(url) }
    }

    // MARK: -

    /// Build the engine graph, create the AAC file, and start capture. Called
    /// once at start, and a second time (voiceProcessing: false) if the shared
    /// digital-silence recovery trips.
    private func attach(voiceProcessing: Bool, reusingFile: Bool = false) throws {
        engine = AVAudioEngine()
        let input = engine.inputNode

        var voice = voiceProcessing && !reusingFile
        if voice {
            do {
                try input.setVoiceProcessingEnabled(true)
                // The live voice unit makes macOS treat the session like a
                // call and duck all other audio — meetings played through the
                // speakers would get quieter the moment recording starts.
                input.voiceProcessingOtherAudioDuckingConfiguration =
                    .init(enableAdvancedDucking: false, duckingLevel: .min)
            } catch {
                FileHandle.standardError.write(Data(
                    "warning: mic voice processing unavailable (\(error)) — recording raw mic\n".utf8
                ))
                voice = false
            }
        }
        let inputFormat = input.outputFormat(forBus: 0)

        // One explicit mono client format. With voice processing this is the
        // Voice I/O boundary format on both sides of the duplex unit — never
        // accept the inherited multichannel route format (a 9-channel device
        // yielded digital silence). Raw capture downmixes to the same shape;
        // speech models want one channel anyway.
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw RecorderError.formatUnsupported(inputFormat)
        }

        if reusingFile {
            guard let existing = state.withLock({ $0.file }) else {
                throw RecorderError.missingExistingFile
            }
            try installRawTap(
                on: input,
                inputFormat: inputFormat,
                monoFormat: existing.processingFormat
            )
            engine.prepare()
            do {
                try engine.start()
            } catch {
                input.removeTap(onBus: 0)
                throw RecorderError.engineStartFailed(error)
            }
            state.withLock {
                $0.failure = nil
                $0.zeroFilledSince = nil
            }
            return
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: monoFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        do {
            let output = try AVAudioFile(
                forWriting: url!,
                settings: settings,
                commonFormat: monoFormat.commonFormat,
                interleaved: monoFormat.isInterleaved
            )
            try SecureStorage.protectFile(url!)
            state.withLock {
                $0.file = output
                $0.failure = nil
                $0.zeroFilledSince = nil
                $0.digitalSilenceRecoveryScheduled = false
            }
        } catch {
            throw RecorderError.fileCreationFailed(error)
        }

        if voice {
            // Complete the duplex graph: VoiceProcessingIO must render to an
            // output device or the input side never produces audio. The mixer
            // has no sources — nothing is monitored or played — its connection
            // exists solely to give the unit a formatted output path.
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: monoFormat)
            installVoiceTap(on: input, format: monoFormat)
        } else {
            try installRawTap(on: input, inputFormat: inputFormat, monoFormat: monoFormat)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            state.withLock { $0.file = nil }
            throw RecorderError.engineStartFailed(error)
        }

        let report = "mic: voiceProcessing=\(input.isVoiceProcessingEnabled) "
            + "input=\(input.outputFormat(forBus: 0)) tap=\(monoFormat)\n"
        FileHandle.standardError.write(Data(report.utf8))
    }

    /// Voice-processing path: the unit converts to the mono client format
    /// itself, so tapped buffers write straight to the file.
    private func installVoiceTap(on input: AVAudioInputNode, format: AVAudioFormat) {
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.write(buffer)
        }
    }

    /// Raw path: tap at the device's native format and downmix to mono. Same
    /// sample rate on both sides, so the one-shot convert applies.
    private func installRawTap(
        on input: AVAudioInputNode,
        inputFormat: AVAudioFormat,
        monoFormat: AVAudioFormat
    ) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: monoFormat) else {
            throw RecorderError.formatUnsupported(inputFormat)
        }
        let sameRate = inputFormat.sampleRate == monoFormat.sampleRate
        let ratio = monoFormat.sampleRate / inputFormat.sampleRate
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let mono = AVAudioPCMBuffer(
                pcmFormat: monoFormat,
                frameCapacity: AVAudioFrameCount(Double(buffer.frameCapacity) * ratio) + 64
            ) else { return }
            do {
                if sameRate {
                    try converter.convert(to: mono, from: buffer)
                } else {
                    let input = ConverterInput(buffer)
                    var conversionError: NSError?
                    converter.convert(to: mono, error: &conversionError) { _, status in
                        if input.supplied {
                            status.pointee = .noDataNow
                            return nil
                        }
                        input.supplied = true
                        status.pointee = .haveData
                        return input.buffer
                    }
                    if let conversionError { throw conversionError }
                }
                self.write(mono)
            } catch {
                self.recordFailure("mic conversion failed: \(error)")
            }
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        let now = Date()
        let hasSignal = Self.hasSignal(buffer)
        let hasNonzeroSample = Self.hasNonzeroSample(buffer)
        guard let file = state.withLock({ $0.file }) else { return }
        do {
            try file.write(from: buffer)
            let shouldRecover = state.withLock {
                if $0.firstBufferAt == nil { $0.firstBufferAt = now }
                $0.lastBufferAt = now
                if hasSignal { $0.lastSignalAt = now }
                if hasNonzeroSample {
                    $0.lastNonzeroAt = now
                    $0.zeroFilledSince = nil
                } else if $0.zeroFilledSince == nil {
                    $0.zeroFilledSince = now
                }
                guard MicrophoneSafety.shouldScheduleRecovery(
                    zeroFilledSince: $0.zeroFilledSince,
                    now: now,
                    recoveryAttempted: $0.digitalSilenceRecoveryAttempted,
                    recoveryScheduled: $0.digitalSilenceRecoveryScheduled
                ) else { return false }
                $0.digitalSilenceRecoveryScheduled = true
                return true
            }
            if shouldRecover {
                DispatchQueue.main.async { [weak self] in
                    self?.recoverFromDigitalSilence()
                }
            }
        } catch {
            recordFailure("mic track write failed: \(error)")
        }
    }

    private func recordFailure(_ message: String) {
        state.withLock { $0.failure = message }
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    private static func hasSignal(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channels = buffer.floatChannelData else { return false }
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<frames where abs(channels[channel][frame]) > 0.0001 {
                return true
            }
        }
        return false
    }

    private static func hasNonzeroSample(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channels = buffer.floatChannelData else { return false }
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<frames where channels[channel][frame] != 0 { return true }
        }
        return false
    }

    /// One conservative recovery attempt for the observed macOS failure mode
    /// where AVAudioEngine remains running but supplies zero-filled buffers.
    /// Preserve the zero-filled attempt for diagnosis, then rebuild the raw
    /// input graph against the current default device.
    private func recoverFromDigitalSilence() {
        guard isRecording, let url else { return }
        let recovery = state.withLock {
            guard !$0.digitalSilenceRecoveryAttempted else {
                $0.digitalSilenceRecoveryScheduled = false
                return (attempt: false, preserveWholeFile: false)
            }
            $0.digitalSilenceRecoveryAttempted = true
            $0.digitalSilenceRecoveryScheduled = false
            return (attempt: true, preserveWholeFile: $0.lastNonzeroAt == nil)
        }
        guard recovery.attempt else { return }

        FileHandle.standardError.write(Data(
            "warning: zero-filled microphone buffers — rebuilding raw mic input\n".utf8
        ))
        notifyUser(
            title: "\(AppIdentity.productName) — repairing microphone",
            body: "Digital silence was detected. The microphone input is being restarted once."
        )

        if !recovery.preserveWholeFile {
            restartCaptureUsingExistingFile(
                failurePrefix: "mic digital-silence recovery failed",
                retryOnFailure: false,
                countsConfigurationChange: false
            )
            return
        }

        configurationRestartPending = true
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        state.withLock { $0.file = nil }
        let evidence = availableEvidenceURL(beside: url)
        do {
            try FileManager.default.moveItem(at: url, to: evidence)
            try SecureStorage.protectFile(evidence)
            state.withLock { $0.preservedZeroFile = evidence.lastPathComponent }
        } catch {
            configurationRestartPending = false
            recordFailure("could not preserve zero-filled mic attempt: \(error)")
            return
        }

        state.withLock {
            $0.firstBufferAt = nil
            $0.lastBufferAt = nil
            $0.lastSignalAt = nil
            $0.lastNonzeroAt = nil
            $0.zeroFilledSince = nil
            $0.failure = nil
        }
        do {
            try attach(voiceProcessing: false)
            configurationRestartPending = false
        } catch {
            configurationRestartPending = false
            recordFailure("mic digital-silence recovery failed: \(error)")
        }
    }

    private func availableEvidenceURL(beside url: URL) -> URL {
        let directory = url.deletingLastPathComponent()
        var candidate = directory.appendingPathComponent("mic.zero-filled.caf")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("mic.zero-filled-\(suffix).caf")
            suffix += 1
        }
        return candidate
    }

    /// Call applications can reconfigure the default input device or its call
    /// profile without revoking microphone permission. AVAudioEngine may then
    /// stop delivering buffers without reporting an error. Reattach after a
    /// short debounce and keep appending to the same CAF so earlier audio and
    /// the session timeline remain intact.
    private func handleConfigurationChange() {
        guard isRecording, !configurationRestartPending else { return }
        configurationRestartPending = true
        FileHandle.standardError.write(Data(
            "mic: input configuration changed — restarting capture\n".utf8
        ))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.restartAfterConfigurationChange()
        }
    }

    private func restartAfterConfigurationChange() {
        configurationRestartPending = false
        guard isRecording else { return }
        restartCaptureUsingExistingFile(
            failurePrefix: "mic restart after input change failed",
            retryOnFailure: true,
            countsConfigurationChange: true
        )
    }

    private func restartCaptureUsingExistingFile(
        failurePrefix: String,
        retryOnFailure: Bool,
        countsConfigurationChange: Bool
    ) {
        guard isRecording else { return }
        configurationRestartPending = true
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        padGapWithSilence()
        do {
            try attach(voiceProcessing: false, reusingFile: true)
            if countsConfigurationChange {
                state.withLock { $0.configurationRestartCount += 1 }
            }
            configurationRestartPending = false
        } catch {
            recordFailure("\(failurePrefix): \(error)")
            guard retryOnFailure else {
                configurationRestartPending = false
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.configurationRestartPending = false
                self.restartAfterConfigurationChange()
            }
        }
    }

    private func padGapWithSilence() {
        let values = state.withLock { ($0.file, $0.lastBufferAt) }
        guard let file = values.0, let lastBufferAt = values.1 else { return }
        let gap = Date().timeIntervalSince(lastBufferAt)
        guard gap > 0.05 else { return }
        let format = file.processingFormat
        var remaining = AVAudioFrameCount(gap * format.sampleRate)
        let chunkSize = AVAudioFrameCount(format.sampleRate)
        while remaining > 0 {
            let count = min(remaining, chunkSize)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
                return
            }
            buffer.frameLength = count
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    channels[channel].update(repeating: 0, count: Int(count))
                }
            }
            do {
                try file.write(from: buffer)
            } catch {
                recordFailure("mic gap padding failed: \(error)")
                return
            }
            remaining -= count
        }
    }

}
