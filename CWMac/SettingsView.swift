//
//  SettingsView.swift
//  CWMac
//
//  The app settings window.
//

import SwiftUI

struct SettingsView: View {
    @Environment(Localization.self) private var loc
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("menuBarMonochrome") private var menuBarMonochrome = true

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
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { loc.language }, set: { loc.language = $0 })
    }
}

#Preview {
    SettingsView()
        .environment(Localization.shared)
}
