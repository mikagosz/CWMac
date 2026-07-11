//
//  CountdownManager.swift
//  CWMac
//
//  Odlicza czas i po jego upływie usypia lub wyłącza Maca.
//

import Foundation
import UserNotifications

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

    private var task: Task<Void, Never>?
    private var warningSent = false

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
    func start(minutes: Int, action: PowerAction) {
        guard minutes > 0 else { return }
        cancel()
        selectedAction = action
        totalSeconds = minutes * 60
        secondsLeft = totalSeconds
        warningSent = false
        lastError = nil
        isRunning = true

        Task { await requestNotificationPermission() }
        task = Task { [weak self] in await self?.runLoop() }
    }

    /// Zatrzymuje odliczanie bez wykonywania akcji.
    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
        secondsLeft = 0
        totalSeconds = 0
        warningSent = false
    }

    private func runLoop() async {
        while secondsLeft > 0 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }

            secondsLeft -= 1

            if !warningSent, warningThreshold > 0, secondsLeft == warningThreshold {
                warningSent = true
                sendWarning()
            }
        }

        isRunning = false
        performAction(selectedAction)
    }

    // MARK: - Wykonanie akcji

    private func performAction(_ action: PowerAction) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        switch action {
        case .sleep:
            process.arguments = ["pmset", "sleepnow"]
        case .shutdown:
            process.arguments = [
                "osascript", "-e",
                "tell application \"System Events\" to shut down"
            ]
        }

        do {
            try process.run()
        } catch {
            lastError = Localization.shared.format("error.action", error.localizedDescription)
        }
    }

    // MARK: - Powiadomienia

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func sendWarning() {
        let content = UNMutableNotificationContent()
        content.title = Localization.shared.string("notif.warningTitle")
        let minutes = max(1, secondsLeft / 60)
        content.body = Localization.shared.format("notif.warningBody", selectedAction.warningPhrase, minutes)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
