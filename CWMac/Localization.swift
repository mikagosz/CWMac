//
//  Localization.swift
//  CWMac
//
//  Prosty, reaktywny system tłumaczeń (PL/EN) działający w SwiftUI i AppKit,
//  z możliwością zmiany języka w locie.
//

import Foundation

/// Dostępne języki interfejsu.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case polish

    var id: String { rawValue }

    /// Klucz nazwy języka w tabeli tłumaczeń.
    var nameKey: String {
        switch self {
        case .system: return "language.system"
        case .english: return "language.english"
        case .polish: return "language.polish"
        }
    }
}

/// Zarządza wyborem języka i dostarcza przetłumaczone teksty.
@MainActor
@Observable
final class Localization {
    static let shared = Localization()

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        language = AppLanguage(rawValue: raw) ?? .system
    }

    /// Aktualny kod języka ("pl" lub "en").
    private var code: String {
        switch language {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("pl") ? "pl" : "en"
        case .english:
            return "en"
        case .polish:
            return "pl"
        }
    }

    /// Zwraca przetłumaczony tekst dla klucza (z fallbackiem na angielski, potem klucz).
    func string(_ key: String) -> String {
        let table = code == "pl" ? Self.pl : Self.en
        return table[key] ?? Self.en[key] ?? key
    }

    /// Zwraca przetłumaczony i sformatowany tekst.
    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }

    // MARK: - Tabele tłumaczeń

    private static let en: [String: String] = [
        "app.subtitle": "Schedule your Mac to sleep or shut down",
        "setup.minutesQuestion": "In how many minutes?",
        "setup.minutesField": "Minutes",
        "setup.start": "Start timer",
        "preset.minFormat": "%d min",
        "run.cancel": "Cancel",
        "quit.help": "Quit app",
        "action.sleep": "Sleep",
        "action.shutdown": "Shut Down",
        "warning.sleep": "Your Mac will sleep",
        "warning.shutdown": "Your Mac will shut down",
        "notif.warningTitle": "Warning!",
        "notif.warningBody": "%1$@ in %2$d min.",
        "error.action": "Could not perform action: %@",
        "menu.statusFormat": "%1$@ in %2$d min",
        "menu.cancel": "Cancel timer",
        "menu.open": "Open CWMac",
        "menu.settings": "Settings…",
        "menu.quit": "Quit CWMac",
        "settings.section.menuBar": "Menu Bar",
        "settings.showIcon": "Show icon in menu bar",
        "settings.iconStyle": "Icon style",
        "settings.iconColor": "Color",
        "settings.iconMono": "Monochrome",
        "settings.section.language": "Language",
        "settings.language": "Language",
        "language.system": "System",
        "language.english": "English",
        "language.polish": "Polski"
    ]

    private static let pl: [String: String] = [
        "app.subtitle": "Zaplanuj uśpienie lub wyłączenie Maca",
        "setup.minutesQuestion": "Za ile minut?",
        "setup.minutesField": "Minuty",
        "setup.start": "Uruchom licznik",
        "preset.minFormat": "%d min",
        "run.cancel": "Anuluj",
        "quit.help": "Zamknij aplikację",
        "action.sleep": "Uśpij",
        "action.shutdown": "Wyłącz",
        "warning.sleep": "Mac zostanie uśpiony",
        "warning.shutdown": "Mac zostanie wyłączony",
        "notif.warningTitle": "Uwaga!",
        "notif.warningBody": "%1$@ za %2$d min.",
        "error.action": "Nie udało się wykonać akcji: %@",
        "menu.statusFormat": "%1$@ za %2$d min",
        "menu.cancel": "Anuluj licznik",
        "menu.open": "Otwórz CWMac",
        "menu.settings": "Ustawienia…",
        "menu.quit": "Zakończ CWMac",
        "settings.section.menuBar": "Pasek menu",
        "settings.showIcon": "Pokaż ikonę w pasku menu",
        "settings.iconStyle": "Styl ikony",
        "settings.iconColor": "Kolorowa",
        "settings.iconMono": "Monochromatyczna",
        "settings.section.language": "Język",
        "settings.language": "Język",
        "language.system": "Systemowy",
        "language.english": "English",
        "language.polish": "Polski"
    ]
}
