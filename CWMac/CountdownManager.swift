//
//  CountdownManager.swift
//  CWMac
//
//  Odlicza czas i po jego upływie usypia lub wyłącza Maca.
//

import AppKit
import Foundation
import UserNotifications

/// Dlaczego polecenie zasilania nie zadziałało.
///
/// Typ celowo nie zna `Localization` — powstaje poza głównym wątkiem, a tłumaczenia
/// żyją na głównym aktorze. Niesie surowe fakty, tekst dla użytkownika składa się
/// dopiero po powrocie na główny wątek.
enum PowerActionError: Error, Sendable {
    /// Użytkownik odmówił zgody na sterowanie System Events (kod -1743).
    case brakZgodyNaAutomatyzacje
    case polecenieZawiodlo(kod: Int32, opis: String)

    @MainActor
    func opisDlaUzytkownika() -> String {
        let loc = Localization.shared
        switch self {
        case .brakZgodyNaAutomatyzacje:
            return loc.string("error.notPermitted")
        case .polecenieZawiodlo(let kod, let opis):
            let szczegol = opis.isEmpty ? loc.string("error.noDetails") : opis
            return loc.format("error.commandFailed", Int(kod), szczegol)
        }
    }
}

/// Zarządza odliczaniem oraz wykonaniem wybranej akcji zasilania.
@MainActor
@Observable
final class CountdownManager {

    /// Współdzielona instancja używana zarówno przez okno, jak i pasek menu.
    static let shared = CountdownManager()

    /// Ile sekund pozostało do wykonania akcji.
    private(set) var secondsLeft: Int = 0

    /// Całkowita liczba sekund ustawiona przy starcie (do obliczania postępu).
    private(set) var totalSeconds: Int = 0

    /// Czy licznik aktualnie odlicza.
    private(set) var isRunning: Bool = false

    /// Akcja, która zostanie wykonana po odliczeniu do zera.
    private(set) var selectedAction: PowerAction = .sleep

    /// Ostatni komunikat błędu (np. gdy nie udało się uruchomić polecenia systemowego).
    var lastError: String?

    /// Moment, w którym licznik ma dobiec zera. `nil`, gdy nic nie odlicza.
    ///
    /// To on jest źródłem prawdy, a nie `secondsLeft`: odliczanie liczone przez
    /// odejmowanie sekundy na obrót pętli spóźnia się o narastającą sumę
    /// narzutów, a przy uśpionym Macu stoi w miejscu. Przy akcji „uśpij" to
    /// szczególnie dotkliwe — licznik zatrzymywałby się dokładnie wtedy, gdy ma
    /// pracować.
    private(set) var deadline: Date?

    /// Wykonuje wybraną akcję zasilania. Podmieniane w testach, żeby zestaw
    /// testów nie mógł uśpić ani wyłączyć maszyny, na której działa.
    @ObservationIgnored
    var actionRunner: @Sendable (PowerAction) throws -> Void = CountdownManager.runSystemAction

    private var task: Task<Void, Never>?
    private var warningSent = false

    /// Wołane przy każdej zmianie stanu licznika — start, tik, koniec, anulowanie.
    ///
    /// Dzięki temu ikona w pasku menu odświeża się **z tego samego tiku**, co
    /// licznik, zamiast pilnować własnego zegara. Wcześniej były dwie niezależne
    /// pętli 1 Hz, więc minuty w pasku bywały o sekundę nieaktualne (P3-03),
    /// a jedna z nich chodziła bez przerwy przez całe życie aplikacji (P2-01).
    @ObservationIgnored
    var onStateChange: (@MainActor () -> Void)?

    /// Czy system zgodził się na powiadomienia. `nil` = jeszcze nie pytaliśmy.
    ///
    /// Gdy zgody nie ma, ostrzeżenie idzie drogą zapasową — inaczej znika bez
    /// śladu, a jest wymienione w README jako funkcja (P2-10).
    @ObservationIgnored
    private(set) var notificationsAllowed: Bool?

    /// Ostrzeżenie pokazane w oknie, gdy powiadomienia systemowe są niedostępne.
    private(set) var fallbackWarning: String?

    /// Postęp odliczania w zakresie 0...1.
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - secondsLeft) / Double(totalSeconds)
    }

    /// Pozostały czas w minutach (zaokrąglony w górę) — do wyświetlenia w pasku menu.
    var minutesRemaining: Int {
        Int((Double(secondsLeft) / 60.0).rounded(.up))
    }

    /// Sformatowany pozostały czas, np. "1:05:09" lub "09:59".
    var formattedTime: String {
        let hours = secondsLeft / 3600
        let minutes = (secondsLeft % 3600) / 60
        let seconds = secondsLeft % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Sekunda przed końcem, przy której wysyłamy ostrzeżenie.
    private var warningThreshold: Int {
        if totalSeconds > 300 { return 300 }   // 5 minut przed końcem
        if totalSeconds > 60 { return 60 }     // 1 minuta przed końcem
        return 0                                // za krótko, aby ostrzegać
    }

    /// Rozpoczyna odliczanie dla podanej liczby minut i wybranej akcji.
    func start(minutes: Int, action: PowerAction, now: Date = Date()) {
        guard minutes > 0 else { return }
        cancel()
        selectedAction = action
        totalSeconds = minutes * 60
        secondsLeft = totalSeconds
        deadline = now.addingTimeInterval(Double(totalSeconds))
        warningSent = false
        lastError = nil
        fallbackWarning = nil
        isRunning = true

        // O zgodę na powiadomienia pytamy RAZ, przy starcie aplikacji — nie przy
        // każdym uruchomieniu licznika w nieprzechowywanym zadaniu (P3-01).
        task = Task { [weak self] in await self?.runLoop() }
        onStateChange?()
    }

    /// Zatrzymuje odliczanie bez wykonywania akcji.
    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
        secondsLeft = 0
        totalSeconds = 0
        deadline = nil
        warningSent = false
        onStateChange?()
    }

    /// Przelicza stan na podaną chwilę i zwraca `true`, gdy czas właśnie minął.
    ///
    /// Wydzielone z pętli, żeby dało się to sprawdzić w teście bez czekania —
    /// wystarczy podać `now` z przyszłości.
    @discardableResult
    func tick(now: Date = Date()) -> Bool {
        guard let deadline else { return false }
        secondsLeft = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))

        // Porównanie nierównością, nie równością: przy liczeniu z zegara
        // ściennego sekundy potrafią przeskoczyć (uśpienie, obciążenie), a
        // ostrzeżenie ma się pojawić także wtedy, gdy dokładna wartość progu
        // została pominięta.
        if !warningSent, warningThreshold > 0, secondsLeft <= warningThreshold, secondsLeft > 0 {
            warningSent = true
            sendWarning()
        }

        guard secondsLeft == 0 else {
            onStateChange?()
            return false
        }
        isRunning = false
        self.deadline = nil
        performAction(selectedAction)
        onStateChange?()
        return true
    }

    private func runLoop() async {
        while deadline != nil {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            if tick() { return }
        }
    }

    // MARK: - Wykonanie akcji

    /// Uruchamia akcję poza głównym wątkiem i melduje wynik.
    ///
    /// Poza głównym wątkiem, bo od teraz **czekamy** na zakończenie polecenia —
    /// czekanie na głównym wątku zamroziłoby interfejs, a przy akcji „wyłącz"
    /// zrobiłoby to dokładnie w chwili, gdy system zaczyna się zamykać.
    private func performAction(_ action: PowerAction) {
        let runner = actionRunner
        actionTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try runner(action)
            } catch let błąd as PowerActionError {
                await MainActor.run { self?.lastError = błąd.opisDlaUzytkownika() }
            } catch {
                await MainActor.run {
                    self?.lastError = Localization.shared.format("error.action", error.localizedDescription)
                }
            }
        }
    }

    /// Uchwyt do trwającej akcji — pozwala testom **poczekać** zamiast zgadywać czas.
    @ObservationIgnored
    private var actionTask: Task<Void, Never>?

    /// Czeka, aż akcja zasilania się dokończy. Bez tego test sprawdzałby stan,
    /// zanim polecenie zdąży cokolwiek zgłosić.
    func waitForAction() async {
        await actionTask?.value
    }

    // MARK: - Szwy testowe
    //
    // Progi ostrzegania są udokumentowaną funkcją o nieoczywistych granicach
    // (przy dokładnie 300 s próg wynosi 60 s, nie 300 s) i **nie miały ani
    // jednego testu**. Audyt 2026-08-01, P2-08. Poniższe trzy szwy istnieją
    // tylko po to, żeby dało się je sprawdzić bez czekania w czasie rzeczywistym.

    var warningThresholdForTesting: Int { warningThreshold }
    var warningSentForTesting: Bool { warningSent }

    func setTotalSecondsForTesting(_ value: Int) {
        totalSeconds = value
    }

    /// Ile najwyżej czekamy na polecenie zasilania, zanim uznamy brak odpowiedzi
    /// za sukces. Przy „wyłącz" system zaczyna się zamykać i proces potomny może
    /// nigdy nie wrócić — limit jest tu obowiązkowy, nie ozdobny.
    nonisolated static let actionTimeout: TimeInterval = 5

    /// Właściwe polecenie systemowe usypiające lub wyłączające Maca.
    ///
    /// Wcześniej kończyło się na `try process.run()`, które rzuca wyjątek **tylko
    /// wtedy, gdy nie da się uruchomić pliku wykonywalnego**. Proces kończący się
    /// kodem błędu — na przykład po odmowie zgody na sterowanie System Events —
    /// był nie do odróżnienia od sukcesu, więc licznik meldował wykonanie akcji,
    /// a Mac zostawał włączony. Audyt 2026-08-01, P1-01.
    nonisolated static func runSystemAction(_ action: PowerAction) throws {
        let process = Process()

        // Ścieżki bezwzględne zamiast `/usr/bin/env`. Aplikacja działa bez
        // piaskownicy, więc rozwiązywanie nazwy przez `PATH` znaczyłoby, że
        // podmieniony wcześniej katalog może podstawić własne „pmset".
        // Audyt 2026-08-01, P2-02.
        switch action {
        case .sleep:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["sleepnow"]
        case .shutdown:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"System Events\" to shut down"]
        }

        let bledy = Pipe()
        process.standardError = bledy
        process.standardOutput = Pipe()

        try process.run()

        let koniecCzekania = Date().addingTimeInterval(actionTimeout)
        while process.isRunning, Date() < koniecCzekania {
            Thread.sleep(forTimeInterval: 0.05)
        }

        // Nie zdążył w limicie — przy „wyłącz" to normalne, bo system już się
        // zamyka. Brak odpowiedzi traktujemy jako sukces, nie jako błąd.
        guard !process.isRunning else { return }
        guard process.terminationStatus != 0 else { return }

        let opis = String(
            decoding: bledy.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // -1743 to systemowy kod „użytkownik nie zezwolił na automatyzację".
        // Wart osobnego komunikatu, bo tylko on da się naprawić kliknięciem.
        if opis.contains("-1743") || opis.localizedCaseInsensitiveContains("not allowed") {
            throw PowerActionError.brakZgodyNaAutomatyzacje
        }
        throw PowerActionError.polecenieZawiodlo(kod: process.terminationStatus, opis: opis)
    }

    // MARK: - Powiadomienia

    /// Pyta o zgodę na powiadomienia i **zapamiętuje odpowiedź**.
    ///
    /// Wcześniej wynik szedł do `_ = try?`, więc odmowa nie zostawiała śladu:
    /// ostrzeżenie przed uśpieniem po prostu nie przychodziło i nikt się o tym
    /// nie dowiadywał. Audyt 2026-08-01, P2-10.
    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            notificationsAllowed = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            notificationsAllowed = false
        }
    }

    private func sendWarning() {
        let loc = Localization.shared
        let minutes = max(1, secondsLeft / 60)
        let tresc = loc.format("notif.warningBody", loc.string(selectedAction.warningPhraseKey), minutes)

        // Droga zapasowa, gdy powiadomień nie ma: napis w oknie plus podskok
        // ikony w Docku. Ostrzeżenie jest funkcją wymienioną w README, więc nie
        // wolno mu zniknąć tylko dlatego, że użytkownik odmówił powiadomień.
        guard notificationsAllowed == true else {
            fallbackWarning = tresc
            NSApplication.shared.requestUserAttention(.criticalRequest)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = loc.string("notif.warningTitle")
        content.body = tresc
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [weak self] błąd in
            guard błąd != nil else { return }
            // Powiadomienie nie weszło mimo zgody — zostaje droga zapasowa.
            Task { @MainActor in
                self?.fallbackWarning = tresc
                NSApplication.shared.requestUserAttention(.criticalRequest)
            }
        }
    }
}
