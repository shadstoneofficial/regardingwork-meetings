import Foundation

struct RecorderSnapshot: Sendable {
    var isRecording: Bool
    var firstBufferAt: Date?
    var lastBufferAt: Date?
    var lastSignalAt: Date?
    var lastNonzeroAt: Date?
    var zeroFilledSince: Date? = nil
    var failure: String?
    var framesWritten: Int64 = 0
    var sampleRate: Double? = nil
    var retryableFailure: Bool = false
}

enum TrackHealthState: String, Codable, Sendable {
    case starting
    case active
    case silent
    case digitalSilence = "digital_silence"
    case stalled
    case failed
    case routeChanged = "route_changed"
    case recovered
    case recovering
    case missing
}

struct TrackHealth: Codable, Equatable, Sendable {
    let state: TrackHealthState
    let detail: String

    var menuText: String {
        switch state {
        case .active: return "✓"
        case .starting: return "…"
        case .recovered: return "recovered"
        case .recovering: return "restarting"
        case .silent: return "silent"
        case .digitalSilence: return "digital silence"
        case .stalled: return "stalled"
        case .failed: return "failed"
        case .routeChanged: return "route changed"
        case .missing: return "missing"
        }
    }

    var needsAttention: Bool {
        ![.active, .starting, .recovered].contains(state)
    }
}

enum TrackHealthEvaluator {
    static let startupGrace: TimeInterval = 5
    static let staleThreshold: TimeInterval = 15
    static let signalThreshold: TimeInterval = 15
    static let digitalSilenceThreshold: TimeInterval = 5

    static func evaluate(
        snapshot: RecorderSnapshot,
        sessionStartedAt: Date,
        now: Date,
        detectDigitalSilence: Bool = false
    ) -> TrackHealth {
        if let failure = snapshot.failure {
            return TrackHealth(state: .failed, detail: failure)
        }
        guard let first = snapshot.firstBufferAt else {
            if now.timeIntervalSince(sessionStartedAt) <= startupGrace {
                return TrackHealth(state: .starting, detail: "waiting for the first audio buffer")
            }
            return TrackHealth(state: .stalled, detail: "no audio buffers have arrived")
        }
        guard let last = snapshot.lastBufferAt,
              now.timeIntervalSince(last) <= staleThreshold
        else {
            return TrackHealth(state: .stalled, detail: "audio buffers stopped arriving")
        }
        if
            detectDigitalSilence,
            let zeroFilledSince = snapshot.zeroFilledSince,
            now.timeIntervalSince(zeroFilledSince) >= digitalSilenceThreshold
        {
            if now.timeIntervalSince(sessionStartedAt) <= digitalSilenceThreshold {
                return TrackHealth(
                    state: .starting,
                    detail: "checking the microphone for a real signal"
                )
            }
            return TrackHealth(
                state: .digitalSilence,
                detail: "microphone buffers contain only digital zeros"
            )
        }
        guard let signal = snapshot.lastSignalAt,
              signal >= first,
              now.timeIntervalSince(signal) <= signalThreshold
        else {
            return TrackHealth(
                state: .silent,
                detail: "buffers are arriving but no audible signal was detected recently"
            )
        }
        return TrackHealth(state: .active, detail: "audio buffers and signal detected")
    }
}

enum MicrophoneSafety {
    static let automaticRecoveryDelay: TimeInterval = 2

    static func shouldScheduleRecovery(
        zeroFilledSince: Date?,
        now: Date,
        recoveryAttempted: Bool,
        recoveryScheduled: Bool
    ) -> Bool {
        guard
            let zeroFilledSince,
            now.timeIntervalSince(zeroFilledSince) >= automaticRecoveryDelay
        else { return false }
        return !recoveryAttempted && !recoveryScheduled
    }

    static func applyingRouteChange(
        to health: TrackHealth,
        startedDevice: AudioInputDeviceIdentity?,
        currentDevice: AudioInputDeviceIdentity?
    ) -> TrackHealth {
        guard let currentDevice else {
            if health.needsAttention {
                return TrackHealth(state: health.state, detail: health.detail + "; current default microphone unavailable")
            }
            return TrackHealth(state: .routeChanged, detail: "current default microphone is unavailable; verify capture and start a new recording")
        }
        guard let startedDevice, startedDevice.uid != currentDevice.uid else { return health }
        if health.needsAttention {
            return TrackHealth(state: health.state,
                detail: health.detail + "; microphone changed from \(startedDevice.name) to \(currentDevice.name)")
        }
        return TrackHealth(
            state: .routeChanged,
            detail: "microphone changed from \(startedDevice.name) to \(currentDevice.name); start a new recording"
        )
    }

    static func menuBarLabel(for state: TrackHealthState) -> String {
        switch state {
        case .starting, .silent: return " CHECK MIC"
        case .digitalSilence, .stalled, .failed, .routeChanged: return " MIC!"
        default: return ""
        }
    }
}

/// Capture remains visibly active (red dot), but no failed track is hidden.
enum CaptureWarningLabel {
    static func text(mic: TrackHealthState, system: TrackHealthState, systemInterrupted: Bool) -> String {
        var labels: [String] = []
        let microphone = MicrophoneSafety.menuBarLabel(for: mic).trimmingCharacters(in: .whitespaces)
        if !microphone.isEmpty { labels.append(microphone) }
        switch system {
        case .stalled, .failed, .missing, .digitalSilence, .routeChanged, .recovering:
            labels.append("SYS!")
        case .starting, .silent:
            labels.append("CHECK SYS")
        case .active, .recovered:
            break
        }
        if systemInterrupted { labels.append("SYS GAP") }
        return labels.isEmpty ? "" : " " + labels.joined(separator: " · ")
    }
}

/// Counts only silence actually committed to disk, even across failed restarts.
struct CaptureGapTimeline {
    private(set) var writtenThrough: Date?

    mutating func noteBuffer(at date: Date) {
        writtenThrough = max(writtenThrough ?? date, date)
    }

    func missingSeconds(until date: Date) -> TimeInterval {
        guard let writtenThrough else { return 0 }
        return max(0, date.timeIntervalSince(writtenThrough))
    }

    mutating func commitPadding(seconds: TimeInterval) {
        guard let writtenThrough, seconds > 0 else { return }
        self.writtenThrough = writtenThrough.addingTimeInterval(seconds)
    }
}

struct CaptureRestartGeneration {
    private(set) var value = 0
    private var active = false

    mutating func start() { value += 1; active = true }
    mutating func stop() { value += 1; active = false }
    func permits(_ token: Int) -> Bool { active && token == value }
}
