import Foundation
import Testing
@testable import RegardingWorkMeetings

@Suite("Onboarding preferences")
struct OnboardingTests {
    @Test("welcome is visible by default and respects the user's choice")
    func showOnLaunchPreference() throws {
        let suite = "RegardingWorkMeetingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(OnboardingPreferences.shouldShowOnLaunch(defaults: defaults))

        OnboardingPreferences.setShowOnLaunch(false, defaults: defaults)
        #expect(!OnboardingPreferences.shouldShowOnLaunch(defaults: defaults))

        OnboardingPreferences.setShowOnLaunch(true, defaults: defaults)
        #expect(OnboardingPreferences.shouldShowOnLaunch(defaults: defaults))

        #expect(!OnboardingPreferences.hasStartedRecording(defaults: defaults))
        OnboardingPreferences.markRecordingStarted(defaults: defaults)
        #expect(OnboardingPreferences.hasStartedRecording(defaults: defaults))
    }
}
