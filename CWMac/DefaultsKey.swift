//
//  DefaultsKey.swift
//  CWMac
//
//  Nazwy kluczy w UserDefaults — w jednym miejscu.
//

import Foundation

/// Klucze trwałych ustawień.
///
/// Wcześniej te same trzy napisy były przepisywane ręcznie w pięciu plikach.
/// Literówka w którymkolwiek nie jest błędem kompilacji — daje ciche powrócenie
/// do wartości domyślnej, czyli objaw typu „przełącznik nic nie robi", którego
/// szuka się długo. Audyt 2026-08-01, P2-07.
///
/// ⚠️ `@AppStorage` w SwiftUI wymaga **stałej literalnej** w niektórych wersjach
/// narzędzi, dlatego w `SettingsView` klucze są powtórzone wprost — ale zaraz obok
/// stoi test, który pilnuje, że oba zapisy są zgodne.
enum DefaultsKey {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let menuBarMonochrome = "menuBarMonochrome"
    static let appLanguage = "appLanguage"

    /// Wartości domyślne rejestrowane przy starcie aplikacji.
    static let defaults: [String: Any] = [
        menuBarMonochrome: true,
        showMenuBarIcon: true,
    ]
}
