//
//  Localization.swift
//  CWMac
//
//  A simple, reactive translation system (PL/EN) that works in both SwiftUI and
//  AppKit, with the language switchable on the fly.
//

import Foundation

/// Available interface languages.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case polish

    var id: String { rawValue }

    /// Key of the language name in the translation table.
    var nameKey: String {
        switch self {
        case .system: return "language.system"
        case .english: return "language.english"
        case .polish: return "language.polish"
        }
    }
}

/// Manages the language choice and supplies translated text.
@MainActor
@Observable
final class Localization {
    static let shared = Localization()

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: DefaultsKey.appLanguage)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.appLanguage) ?? ""
        language = AppLanguage(rawValue: raw) ?? .system
    }

    /// The current language code ("pl" or "en").
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

    /// Returns the translated text for a key (falling back to English, then the key).
    func string(_ key: String) -> String {
        let table = code == "pl" ? Self.pl : Self.en
        return table[key] ?? Self.en[key] ?? key
    }

    /// Returns translated and formatted text.
    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }

    // MARK: - Test seam

    /// Every key used in the interface — the union of both tables.
    ///
    /// A missing translation is not a compile error: the user simply sees the raw
    /// key. A test walking this list is the only sieve for that kind of bug.
    static var allKeysForTesting: [String] {
        Array(Set(en.keys).union(pl.keys)).sorted()
    }

    func hasTranslationForTesting(_ key: String, language: AppLanguage) -> Bool {
        switch language {
        case .english: return Self.en[key] != nil
        case .polish: return Self.pl[key] != nil
        case .system: return Self.en[key] != nil && Self.pl[key] != nil
        }
    }

    // MARK: - Translation tables

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
        "error.notPermitted": "CWMac is not allowed to control System Events, so your Mac was NOT shut down. Allow it in System Settings › Privacy & Security › Automation.",
        "error.commandFailed": "The power command failed (code %1$d) — your Mac was NOT put to sleep or shut down. %2$@",
        "error.noDetails": "The system gave no further details.",
        "setup.actionLabel": "Action",
        "settings.iconHiddenHint": "With no menu bar icon, CWMac runs completely out of sight. To get back to it — and to a running timer — launch CWMac again from Spotlight or Finder.",
        "a11y.settings": "Settings",
        "a11y.quit": "Quit CWMac",
        "a11y.minutesStepper": "Adjust minutes",
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
        "language.polish": "Polski",
        "settings.section.updates": "Updates",
        "settings.checkUpdates": "Check for updates once a month",
        "settings.checkNow": "Check Now",
        "settings.notChecked": "Not checked yet",
        "settings.lastCheck": "Last: %@",
        "settings.updatesPrivacy": "The app asks fractal8.eu for the number of the newest version — it sends nothing else. A new version installs only when you click “Install”.",
        "update.windowTitle": "CWMac — Update",
        "update.newer": "A newer version is available",
        "update.versions": "You have %1$@, version %2$@ is available.",
        "update.explain": "The app downloads the new version, checks it, replaces itself and restarts. Your settings stay.",
        "update.manual": "Download manually and replace it yourself",
        "update.skip": "Skip This Version",
        "update.install": "Install and Restart",
        "update.downloading": "Downloading and verifying the package…",
        "update.installing": "Installing — the app will restart in a moment…",
        "update.busy": "A countdown is running — the restart would cancel it. Cancel the timer first, then click again.",
        "update.checkFailed": "Could not check for updates",
        "update.close": "Close",
        "update.upToDate": "You are up to date",
        "update.version": "Version %@.",
        "update.badAddress": "The package address leads outside fractal8.eu — the app will not download it.",
        "update.notWritable": "The app sits where it cannot be overwritten (e.g. opened straight from Downloads). Move it to the Applications folder or download the new version manually.",
        "update.downloadFailed": "Could not download the new version.",
        "update.installFailed": "Could not install the new version. The app keeps running the current one.",
        "update.restartFailed": "The new version is installed, but the restart failed. Quit and reopen the app manually."
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
        "error.notPermitted": "CWMac nie ma zgody na sterowanie System Events, więc Mac NIE został wyłączony. Zezwól w Ustawieniach systemowych › Prywatność i bezpieczeństwo › Automatyzacja.",
        "error.commandFailed": "Polecenie zasilania zawiodło (kod %1$d) — Mac NIE został uśpiony ani wyłączony. %2$@",
        "error.noDetails": "System nie podał więcej szczegółów.",
        "setup.actionLabel": "Akcja",
        "settings.iconHiddenHint": "Bez ikony w pasku menu CWMac działa całkiem niewidocznie. Żeby do niego wrócić — i do biegnącego licznika — uruchom CWMac ponownie ze Spotlighta albo Findera.",
        "a11y.settings": "Ustawienia",
        "a11y.quit": "Zakończ CWMac",
        "a11y.minutesStepper": "Zmień liczbę minut",
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
        "language.polish": "Polski",
        "settings.section.updates": "Aktualizacje",
        "settings.checkUpdates": "Sprawdzaj aktualizacje raz w miesiącu",
        "settings.checkNow": "Sprawdź teraz",
        "settings.notChecked": "Jeszcze nie sprawdzano",
        "settings.lastCheck": "Ostatnio: %@",
        "settings.updatesPrivacy": "Program pyta stronę fractal8.eu o numer najnowszej wersji — nic więcej nie wysyła. Nowa wersja instaluje się dopiero, gdy klikniesz „Zainstaluj”.",
        "update.windowTitle": "CWMac — Aktualizacja",
        "update.newer": "Jest nowsza wersja",
        "update.versions": "Masz %1$@, dostępna jest %2$@.",
        "update.explain": "Program pobierze nową wersję, sprawdzi ją, podmieni się i uruchomi ponownie. Ustawienia zostają.",
        "update.manual": "Pobierz ręcznie i podmień sam",
        "update.skip": "Pomiń tę wersję",
        "update.install": "Zainstaluj i uruchom ponownie",
        "update.downloading": "Pobieram i sprawdzam paczkę…",
        "update.installing": "Instaluję — za chwilę program uruchomi się ponownie…",
        "update.busy": "Licznik jest uruchomiony — restart by go anulował. Najpierw anuluj licznik, potem kliknij ponownie.",
        "update.checkFailed": "Nie udało się sprawdzić aktualizacji",
        "update.close": "Zamknij",
        "update.upToDate": "Masz najnowszą wersję",
        "update.version": "Wersja %@.",
        "update.badAddress": "Adres paczki prowadzi poza serwer fractal8.eu — program jej nie pobierze.",
        "update.notWritable": "Program stoi w miejscu, którego nie da się nadpisać (np. otwarty prosto z Pobranych). Przenieś go do katalogu Aplikacje albo pobierz nową wersję ręcznie.",
        "update.downloadFailed": "Nie udało się pobrać nowej wersji.",
        "update.installFailed": "Nie udało się zainstalować nowej wersji. Program działa dalej w obecnej.",
        "update.restartFailed": "Nowa wersja jest zainstalowana, ale restart się nie udał. Zamknij i otwórz program ręcznie."
    ]
}
