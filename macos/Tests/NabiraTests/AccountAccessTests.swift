import Foundation
import Testing
@testable import Nabira

@Suite("Account access policy")
struct AccountAccessTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The app is fully available throughout the seven-day trial")
    func trialAccess() {
        let state = AccountAccessSnapshot(
            now: start.addingTimeInterval(7 * 24 * 60 * 60 - 1),
            trialStartedAt: start,
            authenticatedEmail: nil,
            subscriptionStatus: .inactive
        )

        #expect(state.hasAccess)
        #expect(state.isTrialActive)
        #expect(state.trialDaysRemaining == 1)
    }

    @Test("The trial expires exactly after seven days")
    func trialExpiry() {
        let state = AccountAccessSnapshot(
            now: start.addingTimeInterval(7 * 24 * 60 * 60),
            trialStartedAt: start,
            authenticatedEmail: nil,
            subscriptionStatus: .inactive
        )

        #expect(!state.hasAccess)
        #expect(!state.isTrialActive)
        #expect(state.trialDaysRemaining == 0)
    }

    @Test("Signing in without a subscription does not unlock an expired trial")
    func accountAloneIsNotEnough() {
        let state = AccountAccessSnapshot(
            now: start.addingTimeInterval(8 * 24 * 60 * 60),
            trialStartedAt: start,
            authenticatedEmail: "user@example.com",
            subscriptionStatus: .inactive
        )

        #expect(state.isAuthenticated)
        #expect(!state.hasAccess)
    }

    @Test("An authenticated account with an active subscription has access")
    func paidAccountAccess() {
        let state = AccountAccessSnapshot(
            now: start.addingTimeInterval(30 * 24 * 60 * 60),
            trialStartedAt: start,
            authenticatedEmail: "user@example.com",
            subscriptionStatus: .active
        )

        #expect(state.hasAccess)
        #expect(state.hasActiveSubscription)
    }
}
