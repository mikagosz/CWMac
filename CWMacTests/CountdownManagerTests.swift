import Foundation
import Testing
@testable import CWMac

/// CWMac ma jedno zadanie: wykonać akcję zasilania o właściwej porze. Te testy
/// pilnują właśnie tego — że odliczanie trzyma się zegara ściennego, że akcja
/// odpala się dokładnie raz i że anulowanie naprawdę anuluje.
///
/// Każdy test podmienia `actionRunner`, więc żaden nie jest w stanie uśpić ani
/// wyłączyć maszyny, na której leci zestaw.
@MainActor
struct CountdownManagerTests {

    /// Menedżer z podmienioną akcją; `fired` zbiera to, co by się wykonało.
    private final class Spy {
        var fired: [PowerAction] = []
        var shouldThrow: Error?
    }

    private struct StubError: LocalizedError {
        var errorDescription: String? { "stub" }
    }

    private func makeManager() -> (CountdownManager, Spy) {
        let manager = CountdownManager()
        let spy = Spy()
        manager.actionRunner = { action in
            if let error = spy.shouldThrow { throw error }
            spy.fired.append(action)
        }
        return (manager, spy)
    }

    // MARK: - Start i anulowanie

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

    @Test func aTickAfterCancelNeverFiresTheAction() {
        let (manager, spy) = makeManager()
        let now = Date()
        manager.start(minutes: 1, action: .shutdown, now: now)
        manager.cancel()

        // Nawet długo po pierwotnym terminie — anulowany licznik nic nie robi.
        manager.tick(now: now.addingTimeInterval(600))
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

    // MARK: - Odliczanie trzyma się zegara ściennego

    @Test func remainingTimeComesFromTheClockNotFromTickCount() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 60, action: .sleep, now: now)

        // Jeden `tick`, ale zegar przesunął się o 10 minut — tak wygląda powrót
        // z uśpienia albo zadławiona pętla. Liczy się zegar, nie liczba obrotów.
        manager.tick(now: now.addingTimeInterval(600))
        #expect(manager.secondsLeft == 3000)
    }

    @Test func aLongGapDoesNotPushTheDeadlineForward() {
        let (manager, spy) = makeManager()
        let now = Date()
        manager.start(minutes: 30, action: .sleep, now: now)

        // Mac spał dwie godziny. Termin minął dawno — akcja ma pójść od razu,
        // a nie odliczać pozostałe 30 minut od nowa.
        let fired = manager.tick(now: now.addingTimeInterval(7200))
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

    // MARK: - Wykonanie akcji

    @Test func theActionFiresExactlyOnceAtTheDeadline() {
        let (manager, spy) = makeManager()
        let now = Date()
        manager.start(minutes: 1, action: .shutdown, now: now)

        #expect(manager.tick(now: now.addingTimeInterval(59)) == false)
        #expect(spy.fired.isEmpty)

        #expect(manager.tick(now: now.addingTimeInterval(60)))
        #expect(spy.fired == [.shutdown])
        #expect(!manager.isRunning)

        // Kolejne obroty pętli nie mogą wyłączyć Maca po raz drugi.
        manager.tick(now: now.addingTimeInterval(120))
        #expect(spy.fired == [.shutdown])
    }

    @Test func aFailedActionIsReportedInsteadOfSwallowed() {
        let (manager, spy) = makeManager()
        spy.shouldThrow = StubError()
        let now = Date()
        manager.start(minutes: 1, action: .sleep, now: now)
        manager.tick(now: now.addingTimeInterval(60))

        #expect(manager.lastError != nil)
    }

    @Test func startClearsAStaleError() {
        let (manager, spy) = makeManager()
        spy.shouldThrow = StubError()
        let now = Date()
        manager.start(minutes: 1, action: .sleep, now: now)
        manager.tick(now: now.addingTimeInterval(60))
        #expect(manager.lastError != nil)

        spy.shouldThrow = nil
        manager.start(minutes: 5, action: .sleep)
        #expect(manager.lastError == nil)
    }

    // MARK: - Formatowanie

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
        // 1440 minut to maksimum, jakie da się ustawić w oknie.
        manager.start(minutes: 1440, action: .sleep, now: now)
        manager.tick(now: manager.deadline!.addingTimeInterval(-Double(seconds)))
        #expect(manager.formattedTime == expected)
    }

    @Test func minutesRemainingRoundsUpSoItNeverShowsZeroTooEarly() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 10, action: .sleep, now: now)

        manager.tick(now: now.addingTimeInterval(1))     // zostało 599 s
        #expect(manager.minutesRemaining == 10)

        manager.tick(now: now.addingTimeInterval(541))   // zostało 59 s
        #expect(manager.minutesRemaining == 1)
    }
}
