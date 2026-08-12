//
//  DockPresence.swift
//  CWMac
//
//  The single place that decides whether CWMac shows in the Dock.
//

import SwiftUI
import AppKit

/// CWMac is in the Dock exactly as long as one of its own windows is on screen.
///
/// Nothing else enters into it. Not a running countdown, not a standing one, not a
/// hidden menu bar icon. Close the last window and the app drops to `.accessory`
/// and lives on in the menu bar, where everything is reachable anyway: open,
/// settings, cancel and quit.
///
/// This is the owner's design decision, not a defect, and it is written down here
/// so that no future reading of the code mistakes it for one again.
///
/// The rule lives outside the views because that is the only shape it survives in.
/// Written into whichever window happened to be closing, it came back as a bug three
/// times, each time one call site short of being a rule:
///
/// * `P1-02b` — an exception for "no menu bar icon" held the app in the Dock.
/// * `P1-02c` — an exception for "countdown not running" did the same.
/// * `P1-02d` — Settings, opened from the menu bar, switched the app to `.regular`
///   and nothing switched it back on close, leaving the app in the Dock with no
///   window at all.
///
/// A rule spread over several call sites is several rules, and they drift. So there
/// is now exactly one: ``sync()`` looks at which of CWMac's windows are actually on
/// screen and sets the activation policy from that. A window joins the rule by
/// carrying ``SwiftUI/View/dockPresence()``, and no call site is allowed its own
/// opinion about `setActivationPolicy`.
@MainActor
enum DockPresence {

    /// CWMac's own windows.
    ///
    /// A deliberate list rather than a filter over `NSApp.windows`: the menu bar item
    /// and every open menu are windows too as far as AppKit is concerned, and none of
    /// them may hold the app in the Dock.
    ///
    /// Weak, so a closed window that AppKit has released simply drops out — a
    /// released window is not on screen, and a count kept by hand would drift out of
    /// step with reality sooner or later.
    private static let ownWindows = NSHashTable<NSWindow>.weakObjects()

    /// Puts a window under the rule. Called by the probe in ``dockPresence()``.
    static func register(_ window: NSWindow) {
        ownWindows.add(window)
        sync()
    }

    /// Applies the rule to the state AppKit reports right now.
    static func sync() {
        apply(hasWindowOnScreen ? .regular : .accessory)
    }

    /// A window has just appeared, so the rule can only mean `.regular`.
    ///
    /// Stated instead of measured on purpose: `onAppear` can run before the probe has
    /// registered the window, and a ``sync()`` that early would drop the Dock icon for
    /// a moment at launch.
    static func windowDidAppear() {
        apply(.regular)
    }

    /// Applies the rule once the current run loop cycle is over.
    ///
    /// Closing a window finishes asynchronously — asked straight from `onDisappear`,
    /// `isVisible` still reports the window that is on its way out.
    static func syncAfterWindowChange() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { sync() }
        }
    }

    /// Raises the app into the Dock ahead of a window that is about to open, so the
    /// Dock icon and the app menu arrive with the window instead of a cycle later.
    ///
    /// Optimistic, and therefore checked: if the window never turns up — nothing has
    /// registered an opener yet, or the open silently failed — the delayed ``sync()``
    /// takes the app straight back out. That check is the whole difference between
    /// this and the scattered `setActivationPolicy(.regular)` calls it replaces, which
    /// had no way back.
    static func windowWillOpen() {
        apply(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated { sync() }
        }
    }

    private static var hasWindowOnScreen: Bool {
        ownWindows.allObjects.contains { $0.isVisible }
    }

    private static func apply(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }
}

/// Reports the window hosting this view to ``DockPresence``.
///
/// `viewDidMoveToWindow` rather than a deferred look at `view.window`: it fires the
/// moment the view joins a window, which is early enough that the first ``sync()``
/// already sees the truth.
private final class WindowProbe: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            DockPresence.register(window)
        }
    }
}

private struct WindowProbeView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowProbe(frame: .zero) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Places this window under the Dock rule — see ``DockPresence``.
    ///
    /// One modifier rather than a pair of `onAppear` / `onDisappear` handlers, because
    /// the bug came back twice through a window that carried only half of the pair.
    /// Every window scene in CWMac has to have this.
    func dockPresence() -> some View {
        background(WindowProbeView())
            .onAppear { DockPresence.windowDidAppear() }
            .onDisappear { DockPresence.syncAfterWindowChange() }
    }
}
