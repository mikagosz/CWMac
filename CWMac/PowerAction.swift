//
//  PowerAction.swift
//  CWMac
//
//  The action performed when the countdown runs out.
//

import Foundation

/// The kind of action CWMac performs once the countdown reaches zero.
enum PowerAction: String, CaseIterable, Identifiable {
    case sleep
    case shutdown

    var id: String { rawValue }

    // This type deliberately **knows nothing** about `Localization.shared`.
    //
    // It used to reach for the global singleton, which tied a plain data enum to
    // global state and main-actor isolation — harder to test, and mixing the data
    // layer with presentation. Now it hands back keys, and whoever displays the
    // text composes it. Audit 2026-08-01, P2-11.

    /// Key of the label shown to the user.
    var titleKey: String {
        switch self {
        case .sleep: return "action.sleep"
        case .shutdown: return "action.shutdown"
        }
    }

    /// The SF Symbols glyph representing the action.
    var systemImage: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .shutdown: return "power"
        }
    }

    /// Key of the wording used in the warning notification.
    var warningPhraseKey: String {
        switch self {
        case .sleep: return "warning.sleep"
        case .shutdown: return "warning.shutdown"
        }
    }
}
