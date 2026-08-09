//
//  DefaultsKey.swift
//  CWMac
//
//  UserDefaults key names — kept in one place.
//

import Foundation

/// Keys for persisted settings.
///
/// The same three strings used to be retyped by hand across five files. A typo in
/// any of them is not a compile error — it silently falls back to the default
/// value, i.e. the "this switch does nothing" symptom that takes a long time to
/// track down. Audit 2026-08-01, P2-07.
///
/// ⚠️ `@AppStorage` in SwiftUI requires a **literal constant** in some toolchain
/// versions, which is why the keys are repeated verbatim in `SettingsView` — but
/// right beside it stands a test that keeps both spellings in agreement.
enum DefaultsKey {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let menuBarMonochrome = "menuBarMonochrome"
    static let appLanguage = "appLanguage"

    /// Default values registered at app startup.
    static let defaults: [String: Any] = [
        menuBarMonochrome: true,
        showMenuBarIcon: true,
    ]
}
