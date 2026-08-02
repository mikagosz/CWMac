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

    /// Dozwolony zakres minut — jedno miejsce dla `Stepper`, pola tekstowego
    /// i przycisku startu, żeby nie mogły się rozjechać (P2-04).
    static let zakresMinut = 1...1440

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

            // Droga zapasowa ostrzeżenia, gdy powiadomienia systemowe są
            // niedostępne — inaczej znikałoby bez śladu (P2-10).
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
            // `help` to podpowiedź, nie etykieta dostępności — VoiceOver czytał
            // te przyciski jako nieopisane. Audyt 2026-08-01, P2-06.
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
            // Ten przycisk NATYCHMIAST zamyka aplikację — z VoiceOverem był
            // nieopisanym, nieodwracalnym przyciskiem.
            .accessibilityLabel(loc.string("a11y.quit"))
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
            // Zamknięcie okna chowa aplikację do paska menu i usuwa ją z Docka;
            // biegnący licznik działa dalej. To decyzja projektowa, nie usterka:
            // domem CWMac jest pasek menu, a od całkowitego zamknięcia jest
            // przycisk zasilania w oknie.
            //
            // Reguła nie ma wyjątków — ani przy stojącym liczniku, ani przy
            // ukrytej ikonie w pasku menu. Drogą powrotu jest wtedy ponowne
            // uruchomienie CWMac (Finder, Spotlight), które przywraca okno
            // przez `applicationShouldHandleReopen`.
            //
            // Były tu kolejno dwa wyjątki, oba dające ten sam gest o dwóch
            // różnych skutkach zależnie od niewidocznego stanu: „zostań
            // w Docku, gdy ikony w pasku nie ma" (P1-02b) i „chowaj się tylko
            // przy biegnącym liczniku" (P1-02c).
            NSApp.setActivationPolicy(.accessory)
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
            // Etykieta z tabeli tłumaczeń, nie zaszyta po polsku. `labelsHidden()`
            // ukrywa ją wizualnie, ale zostaje tym, co czyta VoiceOver — więc
            // anglojęzyczny użytkownik słyszał polskie „Akcja". Audyt, P2-05.
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
                    Stepper("", value: $minutes, in: Self.zakresMinut)
                        .labelsHidden()
                        .accessibilityLabel(loc.string("a11y.minutesStepper"))
                }
                // `Stepper` miał zakres 1…1440, ale pole tekstowe **żadnego** —
                // z klawiatury przechodziło 99999 minut, czyli 69 dni.
                // Audyt 2026-08-01, P2-04.
                .onChange(of: minutes) { _, nowa in
                    let ograniczona = min(max(nowa, Self.zakresMinut.lowerBound),
                                          Self.zakresMinut.upperBound)
                    if ograniczona != nowa { minutes = ograniczona }
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
            .disabled(!Self.zakresMinut.contains(minutes))
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
