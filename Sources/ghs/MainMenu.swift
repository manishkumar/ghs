import AppKit

/// An `.accessory` app displays no menu bar, which makes it easy to assume it
/// doesn't need one. But the standard editing shortcuts — ⌘V, ⌘C, ⌘X, ⌘A, ⌘Z —
/// are dispatched by `NSApp.mainMenu.performKeyEquivalent`, not by the text
/// field itself. With no main menu, nothing translates the keystroke into a
/// `paste:` action and the field appears to ignore ⌘V, while right-click →
/// Paste still works because the contextual menu sends `paste:` directly.
///
/// Installing this menu fixes editing shortcuts everywhere in the app. The menu
/// itself stays invisible, as accessory apps have no menu bar to show it in.
enum MainMenu {
    static func install(settingsAction: Selector, target: AnyObject) {
        let mainMenu = NSMenu()

        // Application menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: settingsAction, keyEquivalent: ",")
        settings.target = target
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit ghs",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu

        // Edit menu — the reason this file exists.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        // Selectors are built by name because they belong to the responder
        // chain (NSText / NSTextView), not to any type this file can see.
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")

        let pastePlain = NSMenuItem(
            title: "Paste and Match Style",
            action: Selector(("pasteAsPlainText:")),
            keyEquivalent: "V"
        )
        pastePlain.keyEquivalentModifierMask = [.command, .shift, .option]
        editMenu.addItem(pastePlain)

        editMenu.addItem(withTitle: "Delete", action: Selector(("delete:")), keyEquivalent: "")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu

        // Window menu, so ⌘W closes the settings window.
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
