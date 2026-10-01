//
//  SettingsView.swift
//  CWMac
//
//  The app settings window.
//

import SwiftUI
import Combine

struct SettingsView: View {
    @Environment(Localization.self) private var loc
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("menuBarMonochrome") private var menuBarMonochrome = true
    @AppStorage("checkUpdates") private var checkUpdates = true
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        Form {
            Section(loc.string("settings.section.menuBar")) {
                Toggle(loc.string("settings.showIcon"), isOn: $showMenuBarIcon)
                if !showMenuBarIcon {
                    // Hiding the icon is allowed and changes nothing in the Dock
                    // — which is why this text has to say how to get back to the
                    // app once it is gone from both the bar and the Dock (P1-02b).
                    Text(loc.string("settings.iconHiddenHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker(loc.string("settings.iconStyle"), selection: $menuBarMonochrome) {
                    Text(loc.string("settings.iconColor")).tag(false)
                    Text(loc.string("settings.iconMono")).tag(true)
                }
                .disabled(!showMenuBarIcon)
            }

            Section(loc.string("settings.section.updates")) {
                Toggle(loc.string("settings.checkUpdates"), isOn: $checkUpdates)
                    .onChange(of: checkUpdates) { _, on in updates.enabled = on }
                HStack {
                    Text(lastCheckText).foregroundStyle(.secondary)
                    Spacer()
                    Button(loc.string("settings.checkNow")) {
                        Task { await updates.check(manually: true) }
                    }
                }
                Text(loc.string("settings.updatesPrivacy"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(loc.string("settings.section.language")) {
                Picker(loc.string("settings.language"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(loc.string(language.nameKey)).tag(language)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .tint(.cwPurple)
        .frame(width: 380)
        // Settings is a window like any other, so it obeys the same Dock rule. Without
        // this it was the hole the rule fell through: opened from the menu bar it put
        // CWMac in the Dock, and closing it left the app there with nothing on screen
        // (P1-02d).
        .dockPresence()
    }

    private var lastCheckText: String {
        guard let date = updates.lastCheck else { return loc.string("settings.notChecked") }
        return loc.format("settings.lastCheck", date.formatted(date: .abbreviated, time: .shortened))
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { loc.language }, set: { loc.language = $0 })
    }
}

#Preview {
    SettingsView()
        .environment(Localization.shared)
}
