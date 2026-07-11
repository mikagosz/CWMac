//
//  PowerAction.swift
//  CWMac
//
//  Akcja wykonywana po upływie licznika.
//

import Foundation

/// Rodzaj akcji, jaką CWMac wykona po odliczeniu czasu do zera.
enum PowerAction: String, CaseIterable, Identifiable {
    case sleep
    case shutdown

    var id: String { rawValue }

    /// Etykieta wyświetlana użytkownikowi.
    var title: String {
        switch self {
        case .sleep: return Localization.shared.string("action.sleep")
        case .shutdown: return Localization.shared.string("action.shutdown")
        }
    }

    /// Symbol SF Symbols reprezentujący akcję.
    var systemImage: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .shutdown: return "power"
        }
    }

    /// Opis użyty w powiadomieniu ostrzegawczym.
    var warningPhrase: String {
        switch self {
        case .sleep: return Localization.shared.string("warning.sleep")
        case .shutdown: return Localization.shared.string("warning.shutdown")
        }
    }
}
