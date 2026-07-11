//
//  SettingsView.swift
//  CWMac
//
//  Okno ustawień aplikacji.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("menuBarMonochrome") private var menuBarMonochrome = true

    var body: some View {
        Form {
            Section("Pasek menu") {
                Toggle("Pokaż ikonę w pasku menu", isOn: $showMenuBarIcon)
                Picker("Styl ikony", selection: $menuBarMonochrome) {
                    Text("Kolorowa").tag(false)
                    Text("Monochromatyczna").tag(true)
                }
                .disabled(!showMenuBarIcon)
            }
        }
        .formStyle(.grouped)
        .tint(.cwPurple)
        .frame(width: 380)
    }
}

#Preview {
    SettingsView()
}
