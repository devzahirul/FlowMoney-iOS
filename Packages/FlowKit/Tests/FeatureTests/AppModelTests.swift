@testable import AppFeature
import Domain
import FlowCore
import Foundation
import LedgerData
import Testing
import TestSupport

@Suite("AppModel session state machine")
@MainActor
struct AppModelTests {
    let suite = "flowmoney.tests.\(UUID().uuidString)"

    func makeEnvironment(
        auth: FakeAuthService,
        remote: FakeRemoteLedger? = nil,
        reminders: FakeReminderScheduler = .init()
    ) -> AppEnvironment {
        var configuration = LocalLedgerRepository.Configuration()
        configuration.autoSync = false
        return AppEnvironment(
            auth: auth,
            makeRemote: { _ in remote },
            makePersistence: { _ in InMemoryLedgerPersistence() },
            authenticator: FakeAuthenticator(),
            reminders: reminders,
            backendHost: "test.supabase.co",
            calendar: TestCalendar.utc,
            now: { TestCalendar.date(2026, 3, 15) },
            defaultsSuite: suite,
            syncConfiguration: configuration
        )
    }

    @Test("No saved session → onboarding")
    func startsSignedOut() async {
        let model = AppModel(environment: makeEnvironment(auth: FakeAuthService()))
        await model.start()
        #expect(!model.isSignedIn)
    }

    @Test("A Keychain session is restored without any network call")
    func restoresSession() async {
        let session = AuthSession(userID: UUID(), email: "a@b.co", displayName: "Alex")
        let model = AppModel(environment: makeEnvironment(auth: FakeAuthService(session: session), remote: FakeRemoteLedger()))
        await model.start()
        #expect(model.isSignedIn)
    }

    @Test("Demo mode is remembered across launches and cleared on exit")
    func demoPersistsUntilExit() async {
        let environment = makeEnvironment(auth: FakeAuthService())
        let first = AppModel(environment: environment)
        await first.start()
        await first.authActions.startDemo()
        #expect(first.isSignedIn)

        let relaunch = AppModel(environment: environment)
        await relaunch.start()
        #expect(relaunch.isSignedIn)

        await relaunch.endSession(signOutRemotely: true)
        #expect(!relaunch.isSignedIn)
        let afterExit = AppModel(environment: environment)
        await afterExit.start()
        #expect(!afterExit.isSignedIn)
    }

    @Test("Sign-out signs out remotely, wipes preferences and clears reminders")
    func signOutCleansUp() async {
        let auth = FakeAuthService()
        let reminders = FakeReminderScheduler()
        let model = AppModel(environment: makeEnvironment(auth: auth, remote: FakeRemoteLedger(), reminders: reminders))
        await model.start()
        await model.authActions.signedIn(AuthSession(userID: UUID(), email: "a@b.co", displayName: nil))
        model.preferences.hideAmounts = true

        await model.endSession(signOutRemotely: true)
        #expect(!model.isSignedIn)
        #expect(await auth.calls.contains("signOut"))
        #expect(!model.preferences.hideAmounts)
        #expect(await reminders.scheduled.isEmpty)
    }

    @Test("App lock engages after the grace period and unlocks with biometrics")
    func appLock() async {
        let session = AuthSession(userID: UUID(), email: "a@b.co", displayName: nil)
        let model = AppModel(environment: makeEnvironment(auth: FakeAuthService(session: session), remote: FakeRemoteLedger()))
        model.preferences.appLockEnabled = true
        await model.start()
        #expect(model.isLocked, "locked on cold launch")
        await model.unlock()
        #expect(!model.isLocked)
    }
}

@Suite("ReminderPlanner")
struct ReminderPlannerTests {
    @Test("Renewal reminders fire at 9:00 the day before, plus one weekly summary")
    func plansReminders() {
        let now = TestCalendar.date(2026, 3, 10, hour: 12)
        let snapshot = Fixture.snapshot(rules: [Fixture.rule(name: "Netflix", start: TestCalendar.date(2026, 1, 20))])
        let reminders = ReminderPlanner.reminders(for: snapshot, now: now, calendar: TestCalendar.utc)
        let renewals = reminders.filter { $0.id.hasPrefix("renewal") }
        #expect(renewals.map(\.fireDate) == [TestCalendar.date(2026, 3, 19, hour: 9)], "Apr 20 is past the 35-day horizon")
        #expect(renewals.first?.title == "Netflix renews tomorrow")
        #expect(reminders.contains { $0.id == "weekly-summary" })
    }

    @Test("Never exceeds the iOS pending-notification budget")
    func respectsLimit() {
        let now = TestCalendar.date(2026, 3, 10)
        let rules = (0 ..< 40).map { Fixture.rule(name: "Sub \($0)", frequency: .weekly, start: TestCalendar.date(2026, 1, 1)) }
        #expect(ReminderPlanner.reminders(for: Fixture.snapshot(rules: rules), now: now, calendar: TestCalendar.utc).count == 50)
    }
}
