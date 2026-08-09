//
//  CWMacApp.swift
//  CWMac
//
//  Created by mikagosz on 11/07/2026.
//

import SwiftUI
import AppKit

/// Keeps the app alive after the window is closed and creates the menu bar icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: DefaultsKey.defaults)
        statusController = StatusItemController(manager: .shared)

        // Once, at startup — not on every countdown start (P3-01).
        Task { await CountdownManager.shared.requestNotificationPermission() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking CWMac in the Dock, Finder or Spotlight should bring the window back.
    ///
    /// A cheap safety net for every path where the user lost sight of the app —
    /// without it, launching an already running instance can do nothing at all
    /// (audit 2026-08-01, P1-02).
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
