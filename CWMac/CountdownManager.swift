//
//  CountdownManager.swift
//  CWMac
//
//  Counts down and, when the time is up, puts the Mac to sleep or shuts it down.
//

import AppKit
import Foundation
import UserNotifications

/// Why a power command did not work.
///
/// The type deliberately knows nothing about `Localization` — it is created off the
/// main thread, while translations live on the main actor. It carries raw facts; the
/// user-facing text is composed only after returning to the main thread.
enum PowerActionError: Error, Sendable {
    /// The user denied permission to control System Events (code -1743).
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

/// Manages the countdown and the execution of the selected power action.
@MainActor
@Observable
final class CountdownManager {

    /// Shared instance used by both the window and the menu bar.
    static let shared = CountdownManager()

    /// How many seconds are left before the action runs.
    private(set) var secondsLeft: Int = 0

    /// Total number of seconds set at start (used to compute progress).
    private(set) var totalSeconds: Int = 0

    /// Whether the countdown is currently running.
    private(set) var isRunning: Bool = false

    /// The action that runs once the countdown reaches zero.
    private(set) var selectedAction: PowerAction = .sleep

    /// The most recent error message (for example when a system command could not be run).
    var lastError: String?

    /// The moment the countdown is due to reach zero. `nil` when nothing is running.
    ///
    /// This is the source of truth, not `secondsLeft`: counting down by subtracting
    /// one second per loop iteration falls behind by the accumulated overhead, and it
    /// stands still while the Mac is asleep. For the "sleep" action that is especially
    /// painful — the countdown would stop exactly when it is supposed to be working.
    private(set) var deadline: Date?

    /// Performs the selected power action. Swapped out in tests so the suite cannot
    /// put the machine it runs on to sleep or shut it down.
    @ObservationIgnored
    var actionRunner: @Sendable (PowerAction) throws -> Void = CountdownManager.runSystemAction

    private var task: Task<Void, Never>?
    private var warningSent = false

    /// Called on every countdown state change — start, tick, finish, cancel.
    ///
    /// This lets the menu bar icon refresh **from the same tick** as the countdown
    /// instead of watching its own clock. There used to be two independent 1 Hz
    /// loops, so the minutes in the menu bar could be a second out of date (P3-03),
    /// and one of them ran non-stop for the entire life of the app (P2-01).
    @ObservationIgnored
    var onStateChange: (@MainActor () -> Void)?

    /// Whether the system granted notification permission. `nil` = not asked yet.
    ///
    /// Without permission the warning takes the fallback route — otherwise it
    /// disappears without a trace, and README lists it as a feature (P2-10).
    @ObservationIgnored
    private(set) var notificationsAllowed: Bool?

    /// Warning shown in the window when system notifications are unavailable.
    private(set) var fallbackWarning: String?

    /// Countdown progress in the 0...1 range.
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - secondsLeft) / Double(totalSeconds)
    }

    /// Remaining time in minutes (rounded up) — for display in the menu bar.
    var minutesRemaining: Int {
        Int((Double(secondsLeft) / 60.0).rounded(.up))
    }

    /// Formatted remaining time, e.g. "1:05:09" or "09:59".
    var formattedTime: String {
        let hours = secondsLeft / 3600
        let minutes = (secondsLeft % 3600) / 60
        let seconds = secondsLeft % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// The second before the end at which the warning is sent.
    private var warningThreshold: Int {
        if totalSeconds > 300 { return 300 }   // 5 minutes before the end
        if totalSeconds > 60 { return 60 }     // 1 minute before the end
        return 0                                // too short to warn
    }

    /// Starts the countdown for the given number of minutes and the selected action.
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

        // Notification permission is requested ONCE, at app startup — not on every
        // countdown start from inside an unretained task (P3-01).
        task = Task { [weak self] in await self?.runLoop() }
        onStateChange?()
    }

    /// Stops the countdown without performing the action.
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

    /// Recomputes state for the given moment and returns `true` when time has just run out.
    ///
    /// Split out of the loop so it can be checked in a test without waiting —
    /// it is enough to pass a `now` from the future.
    @discardableResult
    func tick(now: Date = Date()) -> Bool {
        guard let deadline else { return false }
        secondsLeft = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))

        // Compared with an inequality, not equality: when counting from the wall
        // clock, seconds can jump (sleep, load), and the warning has to appear even
        // when the exact threshold value was skipped over.
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

    // MARK: - Performing the action

    /// Runs the action off the main thread and reports the result.
    ///
    /// Off the main thread because we now **wait** for the command to finish —
    /// waiting on the main thread would freeze the interface, and with the "shut
    /// down" action it would do so exactly when the system starts closing.
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

    /// Handle to the running action — lets tests **wait** instead of guessing at timing.
    @ObservationIgnored
    private var actionTask: Task<Void, Never>?

    /// Waits until the power action finishes. Without this a test would check state
    /// before the command had a chance to report anything.
    func waitForAction() async {
        await actionTask?.value
    }

    // MARK: - Test seams
    //
    // The warning thresholds are a documented feature with non-obvious boundaries
    // (at exactly 300 s the threshold is 60 s, not 300 s) and had **not a single
    // test**. Audit 2026-08-01, P2-08. The three seams below exist only so they can
    // be checked without waiting in real time.

    var warningThresholdForTesting: Int { warningThreshold }
    var warningSentForTesting: Bool { warningSent }

    func setTotalSecondsForTesting(_ value: Int) {
        totalSeconds = value
    }

    /// How long at most we wait for the power command before treating no answer as
    /// success. With "shut down" the system starts closing and the child process may
    /// never return — the limit is mandatory here, not decorative.
    nonisolated static let actionTimeout: TimeInterval = 5

    /// The actual system command that puts the Mac to sleep or shuts it down.
    ///
    /// This used to end at `try process.run()`, which throws **only when the
    /// executable cannot be launched**. A process exiting with an error code — for
    /// example after permission to control System Events was denied — was
    /// indistinguishable from success, so the countdown reported the action as done
    /// while the Mac stayed on. Audit 2026-08-01, P1-01.
    nonisolated static func runSystemAction(_ action: PowerAction) throws {
        let process = Process()

        // Absolute paths instead of `/usr/bin/env`. The app runs unsandboxed, so
        // resolving the name through `PATH` would mean a directory planted earlier
        // could substitute its own "pmset".
        // Audit 2026-08-01, P2-02.
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

        // It did not make the limit — with "shut down" that is normal, because the
        // system is already closing. No answer is treated as success, not an error.
        guard !process.isRunning else { return }
        guard process.terminationStatus != 0 else { return }

        let opis = String(
            decoding: bledy.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // -1743 is the system code for "the user did not allow automation".
        // Worth its own message, because it is the only one a click can fix.
        if opis.contains("-1743") || opis.localizedCaseInsensitiveContains("not allowed") {
            throw PowerActionError.brakZgodyNaAutomatyzacje
        }
        throw PowerActionError.polecenieZawiodlo(kod: process.terminationStatus, opis: opis)
    }

    // MARK: - Notifications

    /// Asks for notification permission and **remembers the answer**.
    ///
    /// The result used to go into `_ = try?`, so a refusal left no trace: the warning
    /// before sleep simply never arrived and nobody ever found out.
    /// Audit 2026-08-01, P2-10.
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

        // Fallback route when notifications are unavailable: a label in the window
        // plus a Dock icon bounce. The warning is a feature listed in README, so it
        // must not disappear just because the user declined notifications.
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
            // The notification did not go through despite permission — the fallback
            // route takes over.
            Task { @MainActor in
                self?.fallbackWarning = tresc
                NSApplication.shared.requestUserAttention(.criticalRequest)
            }
        }
    }
}
