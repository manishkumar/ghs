#if DEBUG
import AppKit
import SwiftUI

/// `ghs --render <dir>` renders the interface offscreen to PNGs with fixed
/// sample data. Screen-capture tools need Screen Recording permission and
/// return only the wallpaper without it; this path always works, and the fixed
/// ages make the oxidation ramp reproducible between runs.
@MainActor
enum DebugRender {
    static var isRequested: Bool { CommandLine.arguments.contains("--render") }

    /// Called from `applicationDidFinishLaunching` so AppKit is fully up: real
    /// controls need a live app to lay out and draw.
    static func run() {
        guard let index = CommandLine.arguments.firstIndex(of: "--render"),
              CommandLine.arguments.count > index + 1
        else { exit(1) }

        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let store = PRStore(settings: AppSettings(defaults: sampleDefaults()))
        store.injectSample(sampleQueue())

        for dark in [false, true] {
            let name = dark ? "dark" : "light"
            write(QueueView(store: store, onOpenSettings: {}),
                  size: CGSize(width: Theme.popoverWidth, height: 560), dark: dark,
                  fitHeight: true,
                  to: directory.appendingPathComponent("queue-\(name).png"))
            for tab in SettingsView.Tab.allCases {
                // Tall enough for the longest pane, then trimmed to what the
                // content actually wants — a fixed height either clips the
                // Queue pane or pads the others with dead space.
                write(SettingsView(store: store, initialTab: tab, height: 660),
                      size: CGSize(width: SettingsView.windowWidth, height: 660), dark: dark,
                      fitHeight: true,
                      to: directory.appendingPathComponent("settings-\(tab.rawValue.lowercased())-\(name).png"))
            }
        }
        renderStatusBarSamples(to: directory.appendingPathComponent("statusbar.png"))
        print("rendered to \(directory.path)")
        exit(0)
    }

    /// Draws through AppKit rather than `ImageRenderer`, which cannot draw
    /// buttons, text fields or scroll views — they come out as yellow
    /// placeholder blocks and empty space.
    private static func write<V: View>(
        _ view: V, size: CGSize, dark: Bool, fitHeight: Bool = false, to url: URL
    ) {
        let backdrop = dark
            ? Color(red: 0.13, green: 0.13, blue: 0.15)
            : Color(red: 0.90, green: 0.91, blue: 0.93)

        var size = size
        if fitHeight {
            // Ask SwiftUI what height the content actually wants, so a
            // screenshot of the popover isn't padded out with dead space.
            let probe = NSHostingView(rootView: AnyView(view))
            probe.frame = CGRect(origin: .zero, size: size)
            probe.layoutSubtreeIfNeeded()
            size.height = ceil(probe.fittingSize.height)
        }

        let root = ZStack { backdrop; view }.frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        // Offscreen but real: a window is what gives the hierarchy a graphics
        // context and lets controls lay themselves out.
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = hosting.appearance
        window.contentView = hosting
        window.orderFront(nil)

        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.45))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

        /// Composes the status bar item over a menu-bar-like ground, at every
    /// state, in both appearances. The menu bar cannot be screen-captured
    /// without Screen Recording permission, so this is the only way to check
    /// that the item is actually legible.
    static func renderStatusBarSamples(to url: URL) {
        let states: [(label: String, count: Int, mine: Int, urgency: Double)] = [
            ("clear", 0, 0, 0.0),
            ("fresh", 4, 1, 0.20),
            ("warm", 12, 3, 0.55),
            ("stale", 42, 7, 0.85),
            ("rust", 200, 12, 1.0),
        ]
        let rowHeight: CGFloat = 24
        let width: CGFloat = 400
        let height = rowHeight * CGFloat(states.count) * 2  // light block then dark

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        var y = height
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            // A translucent menu bar takes its tone from the wallpaper; these
            // stand in for a light-blue desktop and a dark one.
            let ground = dark
                ? NSColor(red: 0.17, green: 0.18, blue: 0.20, alpha: 1)
                : NSColor(red: 0.78, green: 0.84, blue: 0.93, alpha: 1)

            appearance.performAsCurrentDrawingAppearance {
                for state in states {
                    y -= rowHeight
                    ground.setFill()
                    NSRect(x: 0, y: y, width: width, height: rowHeight).fill()

                    let item = StatusItemController.appearance(
                        count: state.count, mine: state.mine,
                        urgency: state.urgency, scheme: dark ? .dark : .light
                    )

                    var x: CGFloat = 12
                    let image = item.image.isTemplate ? tinted(item.image) : item.image
                    image.draw(in: NSRect(
                        x: x, y: y + (rowHeight - image.size.height) / 2,
                        width: image.size.width, height: image.size.height
                    ))
                    x += image.size.width

                    let titleSize = item.title.size()
                    item.title.draw(at: NSPoint(x: x, y: y + (rowHeight - titleSize.height) / 2))

                    NSAttributedString(
                        string: state.label,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 9),
                            .foregroundColor: NSColor.tertiaryLabelColor,
                        ]
                    ).draw(at: NSPoint(x: width - 60, y: y + 6))
                }
            }
        }

        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Template images carry only alpha; the menu bar supplies the ink. Do the
    /// same here so the preview shows what actually appears.
    private static func tinted(_ image: NSImage) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// Proves ⌘V reaches a text field. An `.accessory` app shows no menu bar,
    /// so it is easy to ship without a main menu and never notice that the
    /// standard editing shortcuts stopped working.
    static func checkPasteShortcut() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("pasted-ok", forType: .string)

        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 300, height: 60),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let field = NSTextField(frame: CGRect(x: 10, y: 10, width: 280, height: 24))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)

        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9
        )!
        let handled = NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false

        print("main menu installed: \(NSApp.mainMenu != nil)")
        print("cmd-V dispatched:    \(handled)")
        print("field contents:      '\(field.stringValue)'")
        print("paste shortcut:      \(field.stringValue == "pasted-ok" ? "WORKS" : "BROKEN")")
        window.orderOut(nil)
    }

    // MARK: Sample data

    private static func sampleDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "ghs.render.\(UUID().uuidString)")!
        let repos = [WatchedRepo(input: "cli/cli")!, WatchedRepo(input: "sharkdp/bat")!]
        defaults.set(try? JSONEncoder().encode(repos), forKey: "watchedRepos")
        defaults.set(7.0, forKey: "urgentAfterDays")
        return defaults
    }

    private static func sampleQueue() -> [PullRequest] {
        let reviewed = ViewerReview(state: .approved, coversHead: true)
        let samples: [(String, String, Int, String, Double, Int, [String], Int, Int, ViewerReview?)] = [
            ("Rework the credential helper to survive keychain lockout", "cli/cli", 10423, "mislav", 61, 0, [], 1240, 880, nil),
            ("Paginate files and commits in `gh pr view --json`", "cli/cli", 13340, "babakks", 22, 0, ["manishkumar"], 412, 96, nil),
            ("Add `--editor` flag to `gh issue edit`", "cli/cli", 12942, "samcoe", 9.5, 1, ["williammartin"], 208, 44, reviewed),
            ("Fix syntax highlighting for nested fenced blocks", "sharkdp/bat", 2984, "keith-hall", 4.2, 0, ["sharkdp"], 88, 31, nil),
            ("Cache theme sets between invocations", "sharkdp/bat", 3011, "einfachToll", 1.6, 2, ["sharkdp", "keith-hall"], 156, 12, nil),
            ("Bump the actions group with 3 updates", "cli/cli", 14192, "dependabot", 0.3, 0, ["manishkumar"], 14, 14, nil),
            ("Teach the resolver to fall back to the lockfile", "sharkdp/bat", 3022, "manishkumar", 5.1, 0, ["sharkdp"], 320, 74, nil),
        ]
        return samples.map { title, repo, number, author, days, approvals, reviewers, adds, dels, viewerReview in
            let ready = Date().addingTimeInterval(-days * 86_400)
            return PullRequest(
                id: "\(repo)#\(number)",
                number: number,
                title: title,
                url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
                author: author,
                repo: repo,
                createdAt: ready,
                readyAt: ready,
                approvals: approvals,
                requestedReviewers: reviewers,
                decision: .reviewRequired,
                authorAvatar: nil,
                additions: adds,
                deletions: dels,
                viewerReview: viewerReview
            )
        }
    }
}

extension PRStore {
    /// Render-only seam so the sample queue can bypass the network.
    func injectSample(_ prs: [PullRequest]) {
        pullRequests = prs
        viewerLogin = "manishkumar"
        lastRefresh = Date()
        tokenSource = .ghCLI
        newlyArrived = [prs.last?.id].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }
    }
}
#endif
