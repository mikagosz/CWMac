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
    ///
    /// Za zamkiem, bo od naprawy P1-01 akcja wykonuje się **poza głównym wątkiem**
    /// (czekamy na zakończenie polecenia, a czekanie na głównym wątku zamroziłoby
    /// interfejs). Bez zamka szpieg byłby wyścigiem sam w sobie.
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

    @Test func aTickAfterCancelNeverFiresTheAction() async {
        let (manager, spy) = makeManager()
        let now = Date()
        manager.start(minutes: 1, action: .shutdown, now: now)
        manager.cancel()

        // Nawet długo po pierwotnym terminie — anulowany licznik nic nie robi.
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

    @Test func aLongGapDoesNotPushTheDeadlineForward() async {
        let (manager, spy) = makeManager()
        let now = Date()
        manager.start(minutes: 30, action: .sleep, now: now)

        // Mac spał dwie godziny. Termin minął dawno — akcja ma pójść od razu,
        // a nie odliczać pozostałe 30 minut od nowa.
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

    // MARK: - Wykonanie akcji

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

        // Kolejne obroty pętli nie mogą wyłączyć Maca po raz drugi.
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

    /// Sedno P1-01: odmowa zgody na sterowanie System Events ma dać komunikat,
    /// z którego wynika, że Mac **nie** został wyłączony i co z tym zrobić.
    @Test func aDeniedAutomationPermissionExplainsItself() async {
        let (manager, spy) = makeManager()
        spy.shouldThrow = PowerActionError.brakZgodyNaAutomatyzacje
        let now = Date()
        manager.start(minutes: 1, action: .shutdown, now: now)
        manager.tick(now: now.addingTimeInterval(60))
        await manager.waitForAction()

        let komunikat = manager.lastError ?? ""
        #expect(!komunikat.isEmpty)
        // Musi mówić, że akcja NIE nastąpiła — inaczej brzmi jak drobiazg.
        #expect(komunikat.contains("NIE") || komunikat.contains("NOT"))
        // I musi prowadzić do miejsca, w którym da się to naprawić.
        #expect(komunikat.contains("Automat") || komunikat.contains("Automation"))
    }

    /// Niezerowy kod wyjścia też ma być błędem, nie ciszą.
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

    // MARK: - Ostrzeganie przed akcją (P2-08)

    /// Progi są nieoczywiste: warunek to `totalSeconds > 300`, więc licznik
    /// ustawiony **dokładnie** na 5 minut dostaje próg 60 s, nie 300 s.
    @Test(arguments: [
        (3600, 300),   // godzina → ostrzeżenie 5 min przed
        (301, 300),    // tuż powyżej progu
        (300, 60),     // dokładnie 5 min → już tylko minuta! (łatwo się pomylić)
        (120, 60),     // 2 min → minuta przed
        (61, 60),      // tuż powyżej minuty
        (60, 0),       // dokładnie minuta → za krótko, nie ostrzegamy
        (30, 0),       // pół minuty → nie ostrzegamy
    ])
    func theWarningThresholdFollowsTheDocumentedRule(totalSeconds: Int, expected: Int) {
        let (manager, _) = makeManager()
        manager.start(minutes: max(1, totalSeconds / 60), action: .sleep)
        // Ustawiamy dokładną liczbę sekund, bo `start` przyjmuje tylko minuty.
        manager.setTotalSecondsForTesting(totalSeconds)
        #expect(manager.warningThresholdForTesting == expected)
    }

    @Test func theWarningIsSentOnceWhenTheThresholdIsCrossed() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 10, action: .sleep, now: now)
        #expect(!manager.warningSentForTesting)

        // 6 minut przed końcem — jeszcze nie.
        manager.tick(now: now.addingTimeInterval(240))
        #expect(!manager.warningSentForTesting)

        // 5 minut przed końcem — teraz tak.
        manager.tick(now: now.addingTimeInterval(300))
        #expect(manager.warningSentForTesting)

        // Kolejne tiki nie mogą ostrzec drugi raz.
        manager.tick(now: now.addingTimeInterval(360))
        #expect(manager.warningSentForTesting)
    }

    /// Ostrzeżenie ma się pojawić także wtedy, gdy dokładna sekunda progu
    /// została **przeskoczona** — na przykład po powrocie z uśpienia.
    @Test func theWarningSurvivesASkippedSecond() {
        let (manager, _) = makeManager()
        let now = Date()
        manager.start(minutes: 60, action: .sleep, now: now)

        // Skok prosto z 60 minut do 2 minut przed końcem — próg 300 s minięty.
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
        manager.start(minutes: ContentView.zakresMinut.upperBound, action: .sleep, now: now)
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

/// Reguły, które nie mają gdzie się zepsuć głośno — literówka w kluczu
/// `UserDefaults` albo rozjazd zakresu minut nie są błędem kompilacji.
@MainActor
struct ProjectInvariantsTests {

    /// `@AppStorage` wymaga stałej literalnej, więc klucze są w `SettingsView`
    /// przepisane wprost. Ten test pilnuje, żeby oba zapisy zostały zgodne
    /// — inaczej przełącznik po cichu przestaje cokolwiek robić (P2-07).
    @Test func settingsKeysMatchTheSingleSourceOfTruth() {
        #expect(DefaultsKey.showMenuBarIcon == "showMenuBarIcon")
        #expect(DefaultsKey.menuBarMonochrome == "menuBarMonochrome")
        #expect(DefaultsKey.appLanguage == "appLanguage")
        #expect(DefaultsKey.defaults[DefaultsKey.showMenuBarIcon] as? Bool == true)
        #expect(DefaultsKey.defaults[DefaultsKey.menuBarMonochrome] as? Bool == true)
    }

    /// Pole tekstowe minut ma trzymać ten sam zakres co `Stepper` (P2-04).
    @Test func theMinutesRangeIsSaneAndShared() {
        #expect(ContentView.zakresMinut.lowerBound == 1)
        #expect(ContentView.zakresMinut.upperBound == 1440)
    }

    /// Każdy klucz z tabeli angielskiej musi mieć odpowiednik po polsku
    /// i odwrotnie — inaczej użytkownik dostaje surowy klucz na ekranie.
    @Test func bothLanguageTablesCoverTheSameKeys() {
        let loc = Localization.shared
        for klucz in Localization.allKeysForTesting {
            #expect(loc.hasTranslationForTesting(klucz, language: .english), "brak EN: \(klucz)")
            #expect(loc.hasTranslationForTesting(klucz, language: .polish), "brak PL: \(klucz)")
        }
        // Kontrola: sito musi cokolwiek sprawdzać.
        #expect(Localization.allKeysForTesting.count > 20)
    }

    /// `PowerAction` nie ma prawa znać `Localization` — oddaje klucze (P2-11).
    @Test func powerActionExposesKeysNotTexts() {
        #expect(PowerAction.sleep.titleKey == "action.sleep")
        #expect(PowerAction.shutdown.titleKey == "action.shutdown")
        #expect(PowerAction.sleep.warningPhraseKey == "warning.sleep")
        #expect(PowerAction.shutdown.warningPhraseKey == "warning.shutdown")
    }
}
