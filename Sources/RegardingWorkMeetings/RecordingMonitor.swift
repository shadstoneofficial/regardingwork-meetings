import Foundation

enum RecordingMonitor {
    @MainActor
    static func schedule(interval: TimeInterval = 1, tick: @escaping @MainActor @Sendable () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
