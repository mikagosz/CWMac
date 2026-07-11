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
        UserDefaults.standard.register(defaults: [
            "menuBarMonochrome": true,
            "showMenuBarIcon": true
        ])
        statusController = StatusItemController(manager: .shared)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
