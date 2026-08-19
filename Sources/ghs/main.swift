import AppKit

/// Entry point. `.accessory` keeps ghs out of the Dock and the app switcher —
/// it exists in the status bar and nowhere else.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var store: PRStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugRender.isRequested { DebugRender.run() }
        #endif

        let store = PRStore(settings: AppSettings())
        self.store = store
        let statusItem = StatusItemController(store: store)
        self.statusItem = statusItem
        MainMenu.install(settingsAction: #selector(openSettings), target: self)
        store.start()

        #if DEBUG
        // Debug entry points, used to inspect the UI without clicking.
        if CommandLine.arguments.contains("--open") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                self.statusItem?.showPopover()
            }
        }
        if CommandLine.arguments.contains("--settings") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self.statusItem?.openSettings()
            }
        }

        // `--diagnose` reports what actually got built in the UI layer and
        // exits. Screen capture needs Screen Recording permission and shows
        // only the wallpaper without it, so this is how status-item and window
        // creation get verified.
        if CommandLine.arguments.contains("--diagnose") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self.statusItem?.openSettings()
                try? await Task.sleep(for: .seconds(1.5))
                self.statusItem?.printDiagnostics()
                DebugRender.checkPasteShortcut()
                exit(0)
            }
        }
        #endif
    }

    @objc private func openSettings() {
        statusItem?.openSettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
    }
}

DebugCLI.runIfRequested()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // Held for the process lifetime; NSApplication only keeps a weak delegate.
    objc_setAssociatedObject(app, "ghs.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}
