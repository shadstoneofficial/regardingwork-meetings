@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os.lock

/// Records all system audio output to a file via a Core Audio process tap
/// (macOS 14.2+). No virtual device, no kernel extension — the tap mixes every
/// process's output to stereo and hands us buffers through a private aggregate
/// device. First use triggers the one-time "System Audio Recording" TCC prompt
/// and lights the purple recording indicator while active.
final class SystemAudioRecorder: SystemAudioRecording, @unchecked Sendable {
    enum RecorderError: Error, CustomStringConvertible {
        case tapCreationFailed(OSStatus)
        case tapFormatUnreadable(OSStatus)
        case aggregateCreationFailed(OSStatus)
        case ioProcCreationFailed(OSStatus)
        case deviceStartFailed(OSStatus)
        case fileCreationFailed(Error)

        var description: String {
            switch self {
            case .tapCreationFailed(let s):
                return "process tap creation failed (OSStatus \(s)) — check System Settings → Privacy & Security → Screen & System Audio Recording"
            case .tapFormatUnreadable(let s): return "couldn't read tap stream format (OSStatus \(s))"
            case .aggregateCreationFailed(let s): return "aggregate device creation failed (OSStatus \(s))"
            case .ioProcCreationFailed(let s): return "IO proc creation failed (OSStatus \(s))"
            case .deviceStartFailed(let s): return "device start failed (OSStatus \(s))"
            case .fileCreationFailed(let e): return "output file creation failed: \(e)"
            }
        }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "\(AppIdentity.bundleIdentifier).system-tap")
    private(set) var ownsOutputFile = false

    private struct LockedState {
        var file: AVAudioFile?
        var firstBufferAt: Date?
        var lastBufferAt: Date?
        var lastSignalAt: Date?
        var failure: String?
        var acceptingBuffers = false
        var framesWritten: Int64 = 0
        var sampleRate: Double?
        var retryableFailure = false
    }
    private let state = OSAllocatedUnfairLock(initialState: LockedState())

    deinit { stop() }

    var firstBufferAt: Date? { state.withLock { $0.firstBufferAt } }

    func snapshot() -> RecorderSnapshot {
        return state.withLock {
            RecorderSnapshot(
                isRecording: $0.acceptingBuffers,
                firstBufferAt: $0.firstBufferAt,
                lastBufferAt: $0.lastBufferAt,
                lastSignalAt: $0.lastSignalAt,
                lastNonzeroAt: $0.lastSignalAt,
                zeroFilledSince: nil,
                failure: $0.failure,
                framesWritten: $0.framesWritten,
                sampleRate: $0.sampleRate,
                retryableFailure: $0.retryableFailure
            )
        }
    }

    /// Start capturing system audio, encoding AAC into `url` (use a .caf
    /// extension — interrupted AAC may still require finalization to decode).
    func start(writingToNewFile url: URL, beforeCapture: () throws -> Void) throws {
        precondition(!ownsOutputFile, "A system recorder must not reuse its output file")
        // O_EXCL refuses an existing file or symlink. Only this reserved file
        // can be opened by AVAudioFile, which otherwise truncates its target.
        try SecureStorage.reserveNewFile(url)
        ownsOutputFile = true
        state.withLock { $0.retryableFailure = true } // Tap/device startup errors may recover.

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "\(AppIdentity.productName) system tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else { throw RecorderError.tapCreationFailed(status) }
        tapID = newTapID

        do {
            let format = try tapStreamFormat()
            try createAggregateDevice(tapUUID: description.uuid)
            let file = try makeFile(url: url, format: format)
            try SecureStorage.protectFile(url)
            state.withLock { $0.file = file; $0.sampleRate = format.sampleRate }
            try installIOProc(format: format)
            // The session records the new filename before any callback can write.
            try beforeCapture()
            state.withLock { $0.acceptingBuffers = true }
            let startStatus = AudioDeviceStart(aggregateID, procID)
            guard startStatus == noErr else { throw RecorderError.deviceStartFailed(startStatus) }
            state.withLock { if $0.failure == nil { $0.retryableFailure = false } }
        } catch {
            let retryable: Bool
            if let recorderError = error as? RecorderError {
                if case .fileCreationFailed = recorderError { retryable = false }
                else { retryable = true }
            } else {
                retryable = false // Includes failure to persist the session manifest.
            }
            state.withLock { $0.retryableFailure = retryable }
            stop()
            throw error
        }
    }

    /// Stop capturing and finalize the file. Idempotent.
    func stop() {
        state.withLock { $0.acceptingBuffers = false }
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
        }
        cleanup()
    }

    // MARK: -

    private func tapStreamFormat() throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            throw RecorderError.tapFormatUnreadable(status)
        }
        return format
    }

    private func createAggregateDevice(tapUUID: UUID) throws {
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "regardingwork-meetings-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [] as [[String: Any]],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newAggregateID)
        guard status == noErr else { throw RecorderError.aggregateCreationFailed(status) }
        aggregateID = newAggregateID
    }

    private func makeFile(url: URL, format: AVAudioFormat) throws -> AVAudioFile {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
        ]
        do {
            return try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
        } catch {
            throw RecorderError.fileCreationFailed(error)
        }
    }

    private func installIOProc(format: AVAudioFormat) throws {
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
            [weak self] _, inInputData, _, _, _ in
            guard let self else { return }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                bufferListNoCopy: inInputData,
                deallocator: nil
            ) else {
                self.state.withLock {
                    guard $0.acceptingBuffers else { return }
                    $0.failure = "system tap delivered an incompatible audio buffer"
                    $0.retryableFailure = true
                }
                return
            }
            guard buffer.frameLength > 0 else { return } // Empty callbacks aren't proof of capture.
            let now = Date()
            let hasSignal = Self.hasSignal(buffer)
            self.state.withLock { state in
                guard state.acceptingBuffers, state.failure == nil, let file = state.file else { return }
                do {
                    // Stop takes the same lock before teardown. A late callback
                    // can neither write into a closed file nor another segment.
                    try file.write(from: buffer)
                    if state.firstBufferAt == nil { state.firstBufferAt = now }
                    state.lastBufferAt = now
                    state.framesWritten += Int64(buffer.frameLength)
                    if hasSignal { state.lastSignalAt = now }
                } catch {
                    state.failure = "system track write failed: \(error)"
                    state.retryableFailure = false // Storage failures must not create a retry loop.
                    FileHandle.standardError.write(Data("system track write failed; capture halted\n".utf8))
                }
            }
        }
        guard status == noErr, procID != nil else { throw RecorderError.ioProcCreationFailed(status) }
    }

    private func cleanup() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        state.withLock { $0.file = nil }
    }

    static func hasSignal(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channels = buffer.floatChannelData else { return false }
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<frames where abs(channels[channel][frame * buffer.stride]) > 0.0001 {
                return true
            }
        }
        return false
    }
}
