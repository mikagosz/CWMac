//
//  ContentView.swift
//  CWMac
//
//  Ekran główny: ustawianie czasu i akcji oraz podgląd odliczania.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(CountdownManager.self) private var manager
    @Environment(Localization.self) private var loc
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var minutes: Int = 60
    @State private var action: PowerAction = .sleep

    private let presets = [15, 30, 60, 120]

    var body: some View {
        VStack(spacing: 24) {
            header

            if manager.isRunning {
                runningView
            } else {
                setupView
            }

            if let error = manager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(width: 360)
        .overlay(alignment: .topLeading) {
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(loc.string("menu.settings"))
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(loc.string("quit.help"))
            .padding(10)
        }
        .onAppear {
            // Okno jest widoczne — pokaż aplikację w Docku.
            NSApp.setActivationPolicy(.regular)
            // Zapamiętaj sposoby otwierania okna i ustawień (używane przez pasek menu).
            WindowActions.shared.openMain = { openWindow(id: "main") }
            WindowActions.shared.openSettings = { openSettings() }
        }
        .onDisappear {
            // Zamknięcie okna podczas odliczania chowa aplikację do paska menu
            // i usuwa ją z Docka; licznik działa dalej.
            if manager.isRunning {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    // MARK: - Nagłówek

    private var header: some View {
        VStack(spacing: 6) {
            Image(.appLogo)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
            HStack(spacing: 8) {
                Text("CWMac")
                    .font(.title2.bold())
                Text("v\(appVersion)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            Text(loc.string("app.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Wersja aplikacji odczytana z bundla (CFBundleShortVersionString).
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Ustawienia

    private var setupView: some View {
        VStack(spacing: 20) {
            Picker("Akcja", selection: $action) {
                ForEach(PowerAction.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(spacing: 12) {
                HStack {
                    Text(loc.string("setup.minutesQuestion"))
                        .font(.subheadline)
                    Spacer()
                    TextField(loc.string("setup.minutesField"), value: $minutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $minutes, in: 1...1440)
                        .labelsHidden()
                }

                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { value in
                        Button {
                            minutes = value
                        } label: {
                            Text(loc.format("preset.minFormat", value))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(minutes == value ? Color.cwPurple : nil)
                    }
                }
            }

            Button {
                manager.start(minutes: minutes, action: action)
            } label: {
                Label(loc.string("setup.start"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(minutes < 1)
        }
    }

    // MARK: - Odliczanie

    private var runningView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: manager.progress)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: manager.progress)

                VStack(spacing: 4) {
                    Text(manager.formattedTime)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Label(manager.selectedAction.title, systemImage: manager.selectedAction.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)
            .padding(.top, 4)

            Button(role: .destructive) {
                manager.cancel()
            } label: {
                Label(loc.string("run.cancel"), systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

#Preview {
    ContentView()
        .environment(CountdownManager())
        .environment(Localization.shared)
        .tint(.cwPurple)
}
