//
//  CWMacApp.swift
//  CWMac
//
//  Created by mikagosz on 11/07/2026.
//

import SwiftUI
import AppKit

/// Utrzymuje aplikację przy życiu po zamknięciu okna i tworzy ikonę w pasku menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: DefaultsKey.defaults)
        statusController = StatusItemController(manager: .shared)

        // Raz, przy starcie — nie przy każdym uruchomieniu licznika (P3-01).
        Task { await CountdownManager.shared.requestNotificationPermission() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Kliknięcie w CWMac w Docku, Finderze albo Spotlighcie ma przywracać okno.
    ///
    /// Tania siatka bezpieczeństwa dla wszystkich ścieżek, w których użytkownik
    /// stracił z oczu aplikację — bez tego ponowne uruchomienie działającej już
    /// instancji potrafi nie zrobić nic (audyt 2026-08-01, P1-02).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        WindowActions.shared.openMain?()
        return true
    }
}

@main
struct CWMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let manager = CountdownManager.shared

    var body: some Scene {
        Window("CWMac", id: "main") {
            ContentView()
                .environment(manager)
                .environment(Localization.shared)
                .tint(.cwPurple)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(Localization.shared)
        }
    }
}
