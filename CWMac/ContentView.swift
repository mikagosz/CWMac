//
//  ContentView.swift
//  CWMac
//
//  Main screen: setting the time and the action, plus the countdown view.
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

    /// Allowed range of minutes — one place for the `Stepper`, the text field and
    /// the start button, so that they cannot drift apart (P2-04).
    static let minutesRange = 1...1440

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

            // Fallback route for the warning when system notifications are
            // unavailable — otherwise it would disappear without a trace (P2-10).
            if let warning = manager.fallbackWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
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
            // `help` is a tooltip, not an accessibility label — VoiceOver read these
            // buttons as undescribed. Audit 2026-08-01, P2-06.
            .accessibilityLabel(loc.string("a11y.settings"))
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
            // This button quits the app IMMEDIATELY — under VoiceOver it was an
            // undescribed, irreversible button.
            .accessibilityLabel(loc.string("a11y.quit"))
            .padding(10)
        }
        // Closing the window hides the app into the menu bar and takes it out of the
        // Dock; a running countdown carries on. This is a design decision, not a
        // defect: the menu bar is CWMac's home, and the power button above quits
        // completely. The rule itself, and why it does not live in this file any
        // more, is in `DockPresence`.
        .dockPresence()
        .onAppear {
            // Remember how to open the window and the settings (used by the menu bar).
            WindowActions.shared.openMain = { openWindow(id: "main") }
            WindowActions.shared.openSettings = { openSettings() }
        }
    }

    // MARK: - Header

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

    /// App version read from the bundle (CFBundleShortVersionString).
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Setup

    private var setupView: some View {
        VStack(spacing: 20) {
            // Label from the translation table, not hardcoded in Polish.
            // `labelsHidden()` hides it visually, but it stays what VoiceOver reads —
            // so an English-speaking user heard the Polish "Akcja". Audit, P2-05.
            Picker(loc.string("setup.actionLabel"), selection: $action) {
                ForEach(PowerAction.allCases) { item in
                    Label(loc.string(item.titleKey), systemImage: item.systemImage).tag(item)
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
                    Stepper("", value: $minutes, in: Self.minutesRange)
                        .labelsHidden()
                        .accessibilityLabel(loc.string("a11y.minutesStepper"))
                }
                // The `Stepper` had a 1…1440 range, but the text field had **none** —
                // 99999 minutes, that is 69 days, went straight through from the
                // keyboard. Audit 2026-08-01, P2-04.
                .onChange(of: minutes) { _, newValue in
                    let clamped = min(max(newValue, Self.minutesRange.lowerBound),
                                      Self.minutesRange.upperBound)
                    if clamped != newValue { minutes = clamped }
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
            .disabled(!Self.minutesRange.contains(minutes))
        }
    }

    // MARK: - Countdown

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
                    Label(loc.string(manager.selectedAction.titleKey),
                          systemImage: manager.selectedAction.systemImage)
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
