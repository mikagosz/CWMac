//
//  StatusItemController.swift
//  CWMac
//
//  Menu bar icon built on NSStatusItem — handles a single click (menu)
//  and a double click (opens the window).
//

import AppKit

/// Holds the action that opens the main window, reachable outside the SwiftUI hierarchy.
@MainActor
final class WindowActions {
    static let shared = WindowActions()
    var openMain: (() -> Void)?
    var openSettings: (() -> Void)?
    private init() {}
}

/// Manages the menu bar item and its interactions.
@MainActor
final class StatusItemController: NSObject {

    private let manager: CountdownManager
    private var statusItem: NSStatusItem?
    private var pendingClick: DispatchWorkItem?

    /// Icon kept between refreshes — rebuilt only when the style has actually
    /// changed. `NSImage(named:)` used to be created every second for the entire
    /// life of the app (P2-01).
    private var cachedImage: NSImage?
    private var cachedMono: Bool?

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

        // No clock of its own.
        //
        // There used to be a 1 Hz `Timer` here, created once and never stopped —
        // every second, even when nothing was counting down, a new task was created,
        // two `UserDefaults` keys were read and the button image was replaced. For a
        // tool that sits in the background for days that is a constant energy cost
        // for no reason (P2-01). On top of that, a second clock meant the minutes in
        // the menu bar could be a second out of date against the countdown (P3-03).
        //
        // Now we refresh from the same tick as the countdown…
        manager.onStateChange = { [weak self] in self?.update() }

        // …and settings changes arrive by notification, not by polling.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        update()
    }

    @objc private func settingsChanged() {
        MainActor.assumeIsolated { update() }
    }

    /// Updates the icon and title to match the countdown state and the settings.
    private func update() {
        guard let statusItem else { return }
        let defaults = UserDefaults.standard

        statusItem.isVisible = defaults.bool(forKey: DefaultsKey.showMenuBarIcon)

        // There used to be a guard here that pulled the app back into the Dock when
        // the menu bar icon disappeared. Removed together with the exception in
        // `ContentView` (audit 2026-08-01, P1-02b): the activation policy belongs to
        // the window and has one rule with no exceptions. The escape hatch with a
        // hidden icon is `applicationShouldHandleReopen` — launching CWMac again
        // comes back with the window and with the countdown still running.

        guard statusItem.isVisible, let button = statusItem.button else { return }

        let mono = defaults.bool(forKey: DefaultsKey.menuBarMonochrome)
        if cachedMono != mono {
            let image = NSImage(named: mono ? "MenuBarTemplate" : "MenuBarColor")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = mono
            cachedImage = image
            cachedMono = mono
            button.image = image
            button.imagePosition = .imageLeading
        }

        if manager.isRunning {
            button.attributedTitle = runningTitle()
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    /// Builds the " 30 zzz" title, where "zzz" is an SF Symbol (the slanted one).
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
            // Center the symbol against the height of the text.
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

    // MARK: - Click handling

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
        let clickCount = event?.clickCount ?? 1

        if isRightClick {
            showMenu()
            return
        }

        if clickCount >= 2 {
            // Double click — open the window and cancel the scheduled menu.
            pendingClick?.cancel()
            pendingClick = nil
            openMainWindow()
        } else {
            // Single click — show the menu after a small delay, so that a possible
            // double click can still be detected.
            let work = DispatchWorkItem { [weak self] in
                self?.pendingClick = nil
                self?.showMenu()
            }
            pendingClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
        }
    }

    private func openMainWindow() {
        DockPresence.windowWillOpen()
        WindowActions.shared.openMain?()
    }

    // MARK: - Menu

    private func showMenu() {
        let menu = NSMenu()

        let loc = Localization.shared

        if manager.isRunning {
            let status = NSMenuItem(
                title: loc.format("menu.statusFormat",
                                  loc.string(manager.selectedAction.titleKey),
                                  manager.minutesRemaining),
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)

            addItem(to: menu, title: loc.string("menu.cancel"), action: #selector(cancelCountdown))
            menu.addItem(.separator())
        }

        addItem(to: menu, title: loc.string("menu.open"), action: #selector(openWindowAction))
        addItem(to: menu, title: loc.string("menu.settings"), action: #selector(openSettings))
        menu.addItem(.separator())
        addItem(to: menu, title: loc.string("menu.quit"), action: #selector(quit))

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
        DockPresence.windowWillOpen()
        // Deferred by one run loop cycle — the Settings window does not open
        // reliably while the menu bar menu is closing.
        DispatchQueue.main.async {
            WindowActions.shared.openSettings?()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
