import AppKit
import SwiftUI

/// Owns the status bar item and the popover.
///
/// This is AppKit rather than SwiftUI's `MenuBarExtra` for two reasons: the
/// status item's appearance needs to change with the queue's age, and a
/// `MenuBarExtra` under `.accessory` activation policy can't reliably open a
/// real settings window.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: PRStore
    private let settingsWindow: SettingsWindowController
    private var redrawTask: Task<Void, Never>?

    init(store: PRStore) {
        self.store = store
        self.settingsWindow = SettingsWindowController(store: store)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover()
        startRedrawTimer()
        trackStoreChanges()
    }

    // MARK: Status bar item

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        render()
    }

    private func render() {
        guard let button = statusItem.button else { return }

        guard store.lastError == nil else {
            button.image = Self.mark(rail: nil)
            button.attributedTitle = NSAttributedString(string: "")
            button.appearsDisabled = true
            button.toolTip = store.lastError
            return
        }

        let appearance = Self.appearance(
            count: store.pullRequests.count,
            mine: store.awaitingViewer.count,
            urgency: store.queueUrgency,
            scheme: isDarkMenuBar ? .dark : .light
        )
        button.image = appearance.image
        button.attributedTitle = appearance.title
        button.appearsDisabled = false
        button.toolTip = appearance.tooltip
    }

    struct Appearance {
        let image: NSImage
        let title: NSAttributedString
        let tooltip: String
    }

    /// The whole status bar look, as a pure function so it can be rendered and
    /// inspected offscreen.
    ///
    /// One number: the whole queue. Two numbers made the reader stop and work
    /// out which was which, and a status bar item gets a glance, not a read.
    /// The personal count still exists — it leads the popover and the tooltip —
    /// but it is not what the menu bar shows.
    ///
    /// Two rules learned the hard way. The menu bar is translucent over the
    /// wallpaper, so a fixed colour washes out — a *template* image lets macOS
    /// render it in the right ink for the current bar, including when the bar
    /// is dark or the item is highlighted. And colour is spent only when it
    /// means something, so the item reads as native chrome until the queue
    /// starts to age.
    static func appearance(count: Int, mine: Int, urgency: Double, scheme: ColorScheme) -> Appearance {
        let railIsHot = count > 0 && urgency >= 0.35
        // The numerals turn only once the ramp is deep enough to stay readable
        // on a translucent bar — brass numerals on a pale wallpaper are the
        // weakest thing in the whole palette, so the glyph carries early
        // urgency on its own.
        let numeralsAreHot = count > 0 && urgency >= 0.7
        let oxide = NSColor(Theme.oxidation(urgency, scheme: scheme))

        let title = NSAttributedString(
            string: " " + String(count),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: numeralsAreHot ? oxide : NSColor.labelColor,
            ]
        )

        let queue = count == 1 ? "1 PR waiting on review" : "\(count) PRs waiting on review"
        let tooltip = count == 0
            ? "Nothing waiting on review"
            : queue + " · " + (mine == 0 ? "none on you" : "\(mine) on you")

        return Appearance(
            image: mark(rail: railIsHot ? oxide : nil),
            title: title,
            tooltip: tooltip
        )
    }

    /// The pull request glyph. One symbol, changed here.
    static let symbolName = "arrow.triangle.pull"

    /// The mark at menu bar size.
    ///
    /// A nil colour produces a template image, which macOS tints to match the
    /// bar — including when the bar is dark or the item is highlighted. That is
    /// the default, because a fixed colour on a translucent menu bar washes out
    /// against a light wallpaper. Colour is applied only when the rail has
    /// something to say.
    static func mark(rail: NSColor?) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Review queue")?
            .withSymbolConfiguration(config)
        else { return NSImage(size: NSSize(width: 1, height: 1)) }

        guard let rail else {
            symbol.isTemplate = true
            return symbol
        }

        // Tinting by compositing rather than a palette configuration, so the
        // result is a flat colour regardless of how the symbol is layered.
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            rail.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        tinted.accessibilityDescription = "Review queue"
        return tinted
    }

    private var isDarkMenuBar: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: Popover

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: QueueView(store: store) { [weak self] in
                self?.openSettings()
            }
        )
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        // Without this the popover opens behind the frontmost app's windows,
        // because an accessory app is never automatically activated.
        popover.contentViewController?.view.window?.makeKey()
        Task { await store.refresh() }
    }

    func openSettings() {
        popover.performClose(nil)
        settingsWindow.present()
    }

    #if DEBUG
    func printDiagnostics() {
        let button = statusItem.button
        print("status item button:   \(button != nil ? "present" : "MISSING")")
        print("status item image:    \(button?.image != nil ? "present" : "MISSING")")
        print("status item title:    \(button?.attributedTitle.string ?? "-")")
        print("status item visible:  \(statusItem.isVisible)")
        print("popover configured:   \(popover.contentViewController != nil)")
        let windows = NSApp.windows.filter { $0.isVisible }
        print("visible windows:      \(windows.count)")
        for window in windows {
            print("  · \(window.title.isEmpty ? "<untitled>" : window.title) "
                  + "visible=\(window.isVisible) key=\(window.isKeyWindow) "
                  + "size=\(Int(window.frame.width))x\(Int(window.frame.height))")
        }
    }
    #endif

    // MARK: Live state

    /// Ages drift while the app sits idle, so repaint on a slow timer as well
    /// as on store changes — otherwise a PR crosses the threshold and the menu
    /// bar keeps showing the old colour until something else happens.
    private func startRedrawTimer() {
        redrawTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.render()
            }
        }
    }

    /// `withObservationTracking` fires once, so it re-arms itself after each
    /// change.
    private func trackStoreChanges() {
        withObservationTracking {
            _ = store.pullRequests
            _ = store.lastError
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.render()
                self?.trackStoreChanges()
            }
        }
    }
}
