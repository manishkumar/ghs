import AppKit
import SwiftUI

/// A real `NSWindow`, created once and reused.
///
/// SwiftUI's `SettingsLink` / `openSettings` silently do nothing from a
/// `MenuBarExtra` in an `.accessory` app — that was the "clicking Settings does
/// nothing" bug. Owning the window directly, and explicitly activating the app
/// before showing it, makes it work.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: PRStore

    init(store: PRStore) {
        self.store = store
    }

    func present() {
        if window == nil { window = makeWindow() }
        guard let window else { return }

        // An accessory app has no menu bar presence of its own, so it must ask
        // for activation or the window opens unfocused behind everything.
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsView.windowWidth, height: SettingsView.windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ghs Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
        window.center()
        return window
    }
}
