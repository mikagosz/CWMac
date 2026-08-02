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

    // Ten typ celowo **nie zna** `Localization.shared`.
    //
    // Wcześniej sięgał po globalny singleton, przez co prosty enum danych był
    // związany z globalnym stanem i izolacją głównego aktora — trudniejszy do
    // przetestowania i mieszający warstwę danych z prezentacją. Teraz oddaje
    // klucze, a tekst składa ten, kto go pokazuje. Audyt 2026-08-01, P2-11.

    /// Klucz etykiety wyświetlanej użytkownikowi.
    var titleKey: String {
        switch self {
        case .sleep: return "action.sleep"
        case .shutdown: return "action.shutdown"
        }
    }

    /// Symbol SF Symbols reprezentujący akcję.
    var systemImage: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .shutdown: return "power"
        }
    }

    /// Klucz opisu użytego w powiadomieniu ostrzegawczym.
    var warningPhraseKey: String {
        switch self {
        case .sleep: return "warning.sleep"
        case .shutdown: return "warning.shutdown"
        }
    }
}
