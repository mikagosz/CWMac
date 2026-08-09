import Foundation
import Testing
@testable import CWMac

/// CWMac has one job: perform the power action at the right time. These tests guard
/// exactly that — that the countdown follows the wall clock, that the action fires
/// exactly once, and that cancelling really cancels.
///
/// Every test swaps out `actionRunner`, so none of them is able to put the machine
/// running the suite to sleep or shut it down.
@MainActor
struct CountdownManagerTests {

    /// A manager with the action swapped out; `fired` collects what would have run.
    ///
    /// Behind a lock, because since the P1-01 fix the action runs **off the main
    /// thread** (we wait for the command to finish, and waiting on the main thread
    /// would freeze the interface). Without the lock the spy would be a race itself.
    private final class Spy: @unchecked Sendable {
        private let lock = NSLock()
        private var _fired: [PowerAction] = []
        private var _shouldThrow: Error?

        var fired: [PowerAction] {
            lock.lock(); defer { lock.unlock() }
            return _fired
        }

        var shouldThrow: Error? {
            get { lock.lock(); defer { lock.unlock() }; return _shouldThrow }
            set { lock.lock(); defer { lock.unlock() }; _shouldThrow = newValue }
        }

        func record(_ action: PowerAction) {
            lock.lock(); defer { lock.unlock() }
            _fired.append(action)
        }
    }

    private struct StubError: LocalizedError {
        var errorDescription: String? { "stub" }
    }

    private func makeManager() -> (CountdownManager, Spy) {
        let manager = CountdownManager()
        let spy = Spy()
        manager.actionRunner = { action in
            if let error = spy.shouldThrow { throw error }
            spy.record(action)
        }
        return (manager, spy)
    }

    // MARK: - Start and cancel

    @Test func startSetsUpTheCountdown() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 30, action: .sleep, now: now)

        #expect(manager.isRunning)
        #expect(manager.totalSeconds == 1800)
        #expect(manager.secondsLeft == 1800)
        #expect(manager.selectedAction == .sleep)
        #expect(manager.deadline == now.addingTimeInterval(1800))
    }

    @Test func zeroOrNegativeMinutesDoNothing() {
        let (manager, _) = makeManager()
        manager.start(minutes: 0, action: .shutdown)
        #expect(!manager.isRunning)
        #expect(manager.deadline == nil)

        manager.start(minutes: -5, action: .shutdown)
        #expect(!manager.isRunning)
    }

    @Test func cancelStopsEverything() {
        let (manager, spy) = makeManager()
        manager.start(minutes: 10, action: .shutdown)
        manager.cancel()

        #expect(!manager.isRunning)
        #expect(manager.secondsLeft == 0)
        #expect(manager.totalSeconds == 0)
        #expect(manager.deadline == nil)
        #expect(spy.fired.isEmpty)
    }

    @Test func aTickAfterCancelNeverFiresTheAction() async {
        let (manager, spy) = makeManager()
        let now = Date()
        manager.start(minutes: 1, action: .shutdown, now: now)
        manager.cancel()

        // Even long past the original deadline — a cancelled countdown does nothing.
        manager.tick(now: now.addingTimeInterval(600))
        await manager.waitForAction()
        #expect(spy.fired.isEmpty)
    }

    @Test func startingAgainReplacesThePreviousCountdown() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 60, action: .sleep, now: now)
        manager.start(minutes: 5, action: .shutdown, now: now)

        #expect(manager.totalSeconds == 300)
        #expect(manager.selectedAction == .shutdown)
        #expect(manager.deadline == now.addingTimeInterval(300))
    }

    // MARK: - The countdown follows the wall clock

    @Test func remainingTimeComesFromTheClockNotFromTickCount() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 60, action: .sleep, now: now)

        // One `tick`, but the clock moved by 10 minutes — this is what waking from
        // sleep or a stalled loop looks like. The clock counts, not the iterations.
        manager.tick(now: now.addingTimeInterval(600))
        #expect(manager.secondsLeft == 3000)
    }

    @Test func aLongGapDoesNotPushTheDeadlineForward() async {
        let (manager, spy) = makeManager()
        let now = Date()
        manager.start(minutes: 30, action: .sleep, now: now)

        // The Mac slept for two hours. The deadline passed long ago — the action
        // must fire straight away, not count the remaining 30 minutes over again.
        let fired = manager.tick(now: now.addingTimeInterval(7200))
        await manager.waitForAction()
        #expect(fired)
        #expect(manager.secondsLeft == 0)
        #expect(spy.fired == [.sleep])
    }

    @Test func progressTracksElapsedTime() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 10, action: .sleep, now: now)
        #expect(manager.progress == 0)

        manager.tick(now: now.addingTimeInterval(300))
        #expect(abs(manager.progress - 0.5) < 0.01)
    }

    @Test func progressIsZeroWhenNothingIsRunning() {
        let (manager, _) = makeManager()
        #expect(manager.progress == 0)
    }

    // MARK: - Performing the action

    @Test func theActionFiresExactlyOnceAtTheDeadline() async {
        let (manager, spy) = makeManager()
        let now = Date()
        manager.start(minutes: 1, action: .shutdown, now: now)

        #expect(manager.tick(now: now.addingTimeInterval(59)) == false)
        #expect(spy.fired.isEmpty)

        #expect(manager.tick(now: now.addingTimeInterval(60)))
        await manager.waitForAction()
        #expect(spy.fired == [.shutdown])
        #expect(!manager.isRunning)

        // Further loop iterations must not shut the Mac down a second time.
        manager.tick(now: now.addingTimeInterval(120))
        await manager.waitForAction()
        #expect(spy.fired == [.shutdown])
    }

    @Test func aFailedActionIsReportedInsteadOfSwallowed() async {
        let (manager, spy) = makeManager()
        spy.shouldThrow = StubError()
        let now = Date()
        manager.start(minutes: 1, action: .sleep, now: now)
        manager.tick(now: now.addingTimeInterval(60))
        await manager.waitForAction()

        #expect(manager.lastError != nil)
    }

    @Test func startClearsAStaleError() async {
        let (manager, spy) = makeManager()
        spy.shouldThrow = StubError()
        let now = Date()
        manager.start(minutes: 1, action: .sleep, now: now)
        manager.tick(now: now.addingTimeInterval(60))
        await manager.waitForAction()
        #expect(manager.lastError != nil)

        spy.shouldThrow = nil
        manager.start(minutes: 5, action: .sleep)
        #expect(manager.lastError == nil)
    }

    /// The heart of P1-01: a denied System Events permission has to produce a
    /// message making clear the Mac was **not** shut down, and what to do about it.
    @Test func aDeniedAutomationPermissionExplainsItself() async {
        let (manager, spy) = makeManager()
        spy.shouldThrow = PowerActionError.brakZgodyNaAutomatyzacje
        let now = Date()
        manager.start(minutes: 1, action: .shutdown, now: now)
        manager.tick(now: now.addingTimeInterval(60))
        await manager.waitForAction()

        let komunikat = manager.lastError ?? ""
        #expect(!komunikat.isEmpty)
        // It has to say the action did NOT happen — otherwise it reads like a detail.
        // "NIE" is the Polish wording from the translation table, matched on purpose.
        #expect(komunikat.contains("NIE") || komunikat.contains("NOT"))
        // And it has to point at the place where this can be fixed.
        #expect(komunikat.contains("Automat") || komunikat.contains("Automation"))
    }

    /// A non-zero exit code must be an error too, not silence.
    @Test func aNonZeroExitCodeIsReported() async {
        let (manager, spy) = makeManager()
        spy.shouldThrow = PowerActionError.polecenieZawiodlo(kod: 1, opis: "boom")
        let now = Date()
        manager.start(minutes: 1, action: .sleep, now: now)
        manager.tick(now: now.addingTimeInterval(60))
        await manager.waitForAction()

        let komunikat = manager.lastError ?? ""
        #expect(komunikat.contains("1"))
        #expect(komunikat.contains("boom"))
    }

    // MARK: - Warning before the action (P2-08)

    /// The thresholds are non-obvious: the condition is `totalSeconds > 300`, so a
    /// countdown set to **exactly** 5 minutes gets a 60 s threshold, not 300 s.
    @Test(arguments: [
        (3600, 300),   // an hour → warning 5 min before
        (301, 300),    // just above the threshold
        (300, 60),     // exactly 5 min → only a minute left! (easy to get wrong)
        (120, 60),     // 2 min → a minute before
        (61, 60),      // just above a minute
        (60, 0),       // exactly a minute → too short, no warning
        (30, 0),       // half a minute → no warning
    ])
    func theWarningThresholdFollowsTheDocumentedRule(totalSeconds: Int, expected: Int) {
        let (manager, _) = makeManager()
        manager.start(minutes: max(1, totalSeconds / 60), action: .sleep)
        // We set the exact number of seconds, because `start` only takes minutes.
        manager.setTotalSecondsForTesting(totalSeconds)
        #expect(manager.warningThresholdForTesting == expected)
    }

    @Test func theWarningIsSentOnceWhenTheThresholdIsCrossed() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 10, action: .sleep, now: now)
        #expect(!manager.warningSentForTesting)

        // 6 minutes before the end — not yet.
        manager.tick(now: now.addingTimeInterval(240))
        #expect(!manager.warningSentForTesting)

        // 5 minutes before the end — now it goes.
        manager.tick(now: now.addingTimeInterval(300))
        #expect(manager.warningSentForTesting)

        // Further ticks must not warn a second time.
        manager.tick(now: now.addingTimeInterval(360))
        #expect(manager.warningSentForTesting)
    }

    /// The warning must appear even when the exact threshold second was **skipped**
    /// — for example after waking from sleep.
    @Test func theWarningSurvivesASkippedSecond() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 60, action: .sleep, now: now)

        // A jump straight from 60 minutes to 2 minutes before the end — the 300 s
        // threshold was passed on the way.
        manager.tick(now: now.addingTimeInterval(3480))
        #expect(manager.warningSentForTesting)
    }

    @Test func aShortTimerNeverWarns() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 1, action: .sleep, now: now)

        manager.tick(now: now.addingTimeInterval(30))
        #expect(!manager.warningSentForTesting)
        #expect(manager.fallbackWarning == nil)
    }

    @Test func startResetsTheWarningFlag() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 10, action: .sleep, now: now)
        manager.tick(now: now.addingTimeInterval(300))
        #expect(manager.warningSentForTesting)

        manager.start(minutes: 10, action: .sleep, now: now)
        #expect(!manager.warningSentForTesting)
        #expect(manager.fallbackWarning == nil)
    }

    // MARK: - Formatting

    @Test(arguments: [
        (0, "00:00"),
        (9, "00:09"),
        (59, "00:59"),
        (60, "01:00"),
        (599, "09:59"),
        (3600, "1:00:00"),
        (3909, "1:05:09"),
        (86399, "23:59:59"),
    ])
    func timeIsFormattedForTheDisplay(seconds: Int, expected: String) {
        let (manager, _) = makeManager()
        let now = Date()
        // 1440 minutes is the maximum that can be set in the window.
        manager.start(minutes: ContentView.zakresMinut.upperBound, action: .sleep, now: now)
        manager.tick(now: manager.deadline!.addingTimeInterval(-Double(seconds)))
        #expect(manager.formattedTime == expected)
    }

    @Test func minutesRemainingRoundsUpSoItNeverShowsZeroTooEarly() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 10, action: .sleep, now: now)

        manager.tick(now: now.addingTimeInterval(1))     // 599 s left
        #expect(manager.minutesRemaining == 10)

        manager.tick(now: now.addingTimeInterval(541))   // 59 s left
        #expect(manager.minutesRemaining == 1)
    }
}

/// Rules with nowhere to break loudly — a typo in a `UserDefaults` key or a drift
/// in the minutes range is not a compile error.
@MainActor
struct ProjectInvariantsTests {

    /// `@AppStorage` requires a literal constant, so the keys are written out
    /// verbatim in `SettingsView`. This test keeps both spellings in agreement
    /// — otherwise the switch quietly stops doing anything (P2-07).
    @Test func settingsKeysMatchTheSingleSourceOfTruth() {
        #expect(DefaultsKey.showMenuBarIcon == "showMenuBarIcon")
        #expect(DefaultsKey.menuBarMonochrome == "menuBarMonochrome")
        #expect(DefaultsKey.appLanguage == "appLanguage")
        #expect(DefaultsKey.defaults[DefaultsKey.showMenuBarIcon] as? Bool == true)
        #expect(DefaultsKey.defaults[DefaultsKey.menuBarMonochrome] as? Bool == true)
    }

    /// The minutes text field has to hold the same range as the `Stepper` (P2-04).
    @Test func theMinutesRangeIsSaneAndShared() {
        #expect(ContentView.zakresMinut.lowerBound == 1)
        #expect(ContentView.zakresMinut.upperBound == 1440)
    }

    /// Every key in the English table must have a Polish counterpart and the other
    /// way round — otherwise the user gets a raw key on screen.
    @Test func bothLanguageTablesCoverTheSameKeys() {
        let loc = Localization.shared
        for klucz in Localization.allKeysForTesting {
            #expect(loc.hasTranslationForTesting(klucz, language: .english), "missing EN: \(klucz)")
            #expect(loc.hasTranslationForTesting(klucz, language: .polish), "missing PL: \(klucz)")
        }
        // Control check: the sieve has to be checking something.
        #expect(Localization.allKeysForTesting.count > 20)
    }

    /// `PowerAction` has no business knowing `Localization` — it hands back keys (P2-11).
    @Test func powerActionExposesKeysNotTexts() {
        #expect(PowerAction.sleep.titleKey == "action.sleep")
        #expect(PowerAction.shutdown.titleKey == "action.shutdown")
        #expect(PowerAction.sleep.warningPhraseKey == "warning.sleep")
        #expect(PowerAction.shutdown.warningPhraseKey == "warning.shutdown")
    }
}
