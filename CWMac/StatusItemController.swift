//
//  StatusItemController.swift
//  CWMac
//
//  Ikona w pasku menu oparta na NSStatusItem — obsługuje pojedyncze
//  kliknięcie (menu) oraz podwójne kliknięcie (otwarcie okna).
//

import AppKit

/// Przechowuje akcję otwarcia głównego okna, dostępną poza hierarchią SwiftUI.
@MainActor
final class WindowActions {
    static let shared = WindowActions()
    var openMain: (() -> Void)?
    private init() {}
}

/// Zarządza pozycją w pasku menu i jej interakcjami.
@MainActor
final class StatusItemController: NSObject {

    private let manager: CountdownManager
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var pendingClick: DispatchWorkItem?

    init(manager: CountdownManager) {
        self.manager = manager
        super.init()
        configure()
    }

    private func configure() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        update()

        // Odświeżanie licznika i reagowanie na zmiany ustawień.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    /// Aktualizuje ikonę i tytuł zgodnie ze stanem licznika oraz ustawieniami.
    private func update() {
        guard let statusItem else { return }
        let defaults = UserDefaults.standard

        statusItem.isVisible = defaults.bool(forKey: "showMenuBarIcon")
        guard statusItem.isVisible, let button = statusItem.button else { return }

        let mono = defaults.bool(forKey: "menuBarMonochrome")
        let image = NSImage(named: mono ? "MenuBarTemplate" : "MenuBarColor")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = mono
        button.image = image
        button.imagePosition = .imageLeading

        if manager.isRunning {
            button.attributedTitle = runningTitle()
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    /// Buduje tytuł „ 30 zzz", gdzie „zzz" jest symbolem SF (ukośnym).
    private func runningTitle() -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: 0)
        let title = NSMutableAttributedString(
            string: " \(manager.minutesRemaining) ",
            attributes: [.font: font]
        )

        let config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
        if let symbol = NSImage(systemSymbolName: "zzz", accessibilityDescription: "zzz")?
            .withSymbolConfiguration(config) {
            symbol.isTemplate = true
            let attachment = NSTextAttachment()
            attachment.image = symbol
            // Wyśrodkuj symbol względem wysokości tekstu.
            let height = symbol.size.height
            attachment.bounds = CGRect(
                x: 0,
                y: (font.capHeight - height) / 2,
                width: symbol.size.width,
                height: height
            )
            title.append(NSAttributedString(attachment: attachment))
        }

        return title
    }

    // MARK: - Obsługa kliknięć

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
        let clickCount = event?.clickCount ?? 1

        if isRightClick {
            showMenu()
            return
        }

        if clickCount >= 2 {
            // Podwójne kliknięcie — otwórz okno i anuluj zaplanowane menu.
            pendingClick?.cancel()
            pendingClick = nil
            openMainWindow()
        } else {
            // Pojedyncze kliknięcie — pokaż menu z małym opóźnieniem,
            // aby móc wykryć ewentualne podwójne kliknięcie.
            let work = DispatchWorkItem { [weak self] in
                self?.pendingClick = nil
                self?.showMenu()
            }
            pendingClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
        }
    }

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        WindowActions.shared.openMain?()
    }

    // MARK: - Menu

    private func showMenu() {
        let menu = NSMenu()

        if manager.isRunning {
            let status = NSMenuItem(
                title: "\(manager.selectedAction.title) za \(manager.minutesRemaining) min",
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)

            addItem(to: menu, title: "Anuluj licznik", action: #selector(cancelCountdown))
            menu.addItem(.separator())
        }

        addItem(to: menu, title: "Otwórz CWMac", action: #selector(openWindowAction))
        addItem(to: menu, title: "Ustawienia…", action: #selector(openSettings))
        menu.addItem(.separator())
        addItem(to: menu, title: "Zakończ CWMac", action: #selector(quit))

        if let button = statusItem?.button {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: button.bounds.height + 4),
                in: button
            )
        }
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func cancelCountdown() {
        manager.cancel()
    }

    @objc private func openWindowAction() {
        openMainWindow()
    }

    @objc private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
