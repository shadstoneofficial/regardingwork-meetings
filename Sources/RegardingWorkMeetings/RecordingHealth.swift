import Foundation

struct RecorderSnapshot: Sendable {
    var isRecording: Bool
    var firstBufferAt: Date?
    var lastBufferAt: Date?
    var lastSignalAt: Date?
    var lastNonzeroAt: Date?
    var zeroFilledSince: Date? = nil
    var failure: String?
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
        guard
            let startedDevice,
            let currentDevice,
            startedDevice.uid != currentDevice.uid
        else { return health }
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
