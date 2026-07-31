import Foundation

struct RecorderSnapshot: Sendable {
    var isRecording: Bool
    var firstBufferAt: Date?
    var lastBufferAt: Date?
    var lastSignalAt: Date?
    var failure: String?
}

enum TrackHealthState: String, Codable, Sendable {
    case starting
    case active
    case silent
    case stalled
    case failed
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
        case .stalled: return "stalled"
        case .failed: return "failed"
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

    static func evaluate(
        snapshot: RecorderSnapshot,
        sessionStartedAt: Date,
        now: Date
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
