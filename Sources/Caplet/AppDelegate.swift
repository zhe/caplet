import AppKit
import CapletCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private lazy var hyperKey = HyperKeyController { [weak self] command in self?.run(command) }

    private let permissionItem = NSMenuItem(title: "Grant Accessibility Access…",
                                            action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let takeBackItem = NSMenuItem(title: "Take Back Caps Lock", action: #selector(takeBackCapsLock),
                                          keyEquivalent: "")
    private let appsSeparator = NSMenuItem.separator()
    private let appsHeader = NSMenuItem.header("Apps")
    private var appItems: [NSMenuItem] = []
    /// The menu items running a window command, whose shortcut labels follow the keymap.
    private var commandItems: [NSMenuItem] = []
    private var keymap = Keymap.defaults
    private var settings: SettingsWindowController?
    private var appNotes: [String] = []
    /// Plain title and drawn shortcut label of each item that shows one, and whether Caplet gave
    /// it an icon. `NSMenuItem.image` can't tell: for Quit (`terminate:`) it returns a default
    /// image even after being set to nil, which the status menu doesn't draw.
    private var shortcuts: [ObjectIdentifier: (title: String, label: String, icon: Bool)] = [:]
    private var terminationSignal: DispatchSourceSignal?

    /// How far a menu item's icon pushes its title right. AppKit doesn't expose this, so it's
    /// measured from the menu on macOS 26: titles with icons start 26pt right of those without.
    private static let iconColumnWidth: CGFloat = 26

    private var cyclingEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsWindowController.cyclingKey) as? Bool ?? true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // MenuBarIcon.png is only in the bundled app; `swift run` falls back to a system symbol.
        let icon = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Caplet")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.setAccessibilityLabel("Caplet")
        statusItem.menu = buildMenu()
        reloadKeymap()
        // Unlike didChangeNotification, KVO also reports `defaults write` from other processes.
        UserDefaults.standard.addObserver(self, forKeyPath: Keymap.defaultsKey, context: nil)

        WindowMover.requestTrust()
        hyperKey.onStateChange = { [weak self] in self?.updateIcon() }
        hyperKey.start()
        updateIcon()
        quitOnSIGTERM()
    }

    /// `kill` and `pkill` send SIGTERM, which would otherwise skip
    /// applicationWillTerminate and leave Caps Lock remapped to F18.
    private func quitOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        terminationSignal = source
    }

    /// Dims the menu-bar icon while the ⇪ shortcuts are off.
    private func updateIcon() {
        statusItem.button?.appearsDisabled = hyperKey.state != .active
    }

    func applicationWillTerminate(_ notification: Notification) {
        hyperKey.stop()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        for action in TileAction.allCases {
            if action == .topLeft || action == .maximize { menu.addItem(.separator()) }
            menu.addItem(commandItem(.tile(action)))
        }

        // No submenus: a submenu makes AppKit reserve an arrow column on every row, which leaves
        // a gap right of the drawn shortcut labels.
        menu.addItem(.separator())
        menu.addItem(.header("Arrange"))
        for action in ArrangeAction.allCases { menu.addItem(commandItem(.arrange(action))) }
        // updateApps() lists the apps below the header.
        menu.addItem(appsSeparator)
        menu.addItem(appsHeader)

        menu.addItem(.separator())
        // macOS 26 picks default images by selector, such as a gear for `openSettings` and an
        // xmark for `terminate:` (which the status menu doesn't draw). Rows without an icon clear
        // it, and Settings uses `openSettingsWindow`, which gets none.
        for item in [statusLine, takeBackItem, permissionItem] { item.image = nil }
        statusLine.isEnabled = false
        statusLine.isHidden = true
        menu.addItem(statusLine)
        takeBackItem.target = self
        menu.addItem(takeBackItem)
        permissionItem.target = self
        menu.addItem(permissionItem)
        // Rows with a shortcut label need an icon: a row without one starts left of the others, so
        // its label has to sit further along its title, and AppKit then sizes the menu as if that
        // title started after the icon column too, leaving a gap right of every label.
        menu.addItem(shortcutItem("Settings…", "⌘,", #selector(openSettingsWindow),
                                  image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)))
        menu.addItem(.separator())
        let quit = shortcutItem("Quit Caplet", "⌘Q", #selector(NSApplication.terminate(_:)),
                                image: NSImage(systemSymbolName: "power", accessibilityDescription: nil))
        quit.target = NSApp
        menu.addItem(quit)
        // AppKit draws real key equivalents in a column right of every title, which the drawn
        // ⇪ labels can't line up with. These hidden twins keep ⌘, and ⌘Q working while the menu is open.
        let settingsKey = NSMenuItem(title: "Settings…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsKey.target = self
        let quitKey = NSMenuItem(title: "Quit Caplet", action: #selector(NSApplication.terminate(_:)),
                                 keyEquivalent: "q")
        for item in [settingsKey, quitKey] {
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            menu.addItem(item)
        }
        return menu
    }

    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                           change: [NSKeyValueChangeKey: Any]?,
                                           context: UnsafeMutableRawPointer?) {
        Task { @MainActor in self.reloadKeymap() }
    }

    /// Reads the keymap from UserDefaults, moving the app shortcuts of the old `launchers`
    /// setting into it the first time.
    private func reloadKeymap() {
        let defaults = UserDefaults.standard
        if let saved = Keymap(plist: defaults.object(forKey: Keymap.defaultsKey)) {
            apply(saved)
        } else if let launchers = defaults.object(forKey: Keymap.launchersKey) {
            save(Keymap.migrating(launchers: launchers))
            defaults.removeObject(forKey: Keymap.launchersKey)
        } else {
            apply(.defaults)
        }
    }

    private func save(_ keymap: Keymap) {
        UserDefaults.standard.set(keymap.plist, forKey: Keymap.defaultsKey)
        apply(keymap)
    }

    private func apply(_ keymap: Keymap) {
        self.keymap = keymap
        hyperKey.keymap = keymap
        settings?.keymap = keymap
        updateShortcutLabels()
    }

    @objc private func openSettingsWindow() {
        if settings == nil {
            settings = SettingsWindowController(keymap: keymap) { [weak self] keymap in self?.save(keymap) }
        }
        settings?.show()
    }

    private func commandItem(_ command: HyperCommand) -> NSMenuItem {
        let item = NSMenuItem(title: command.title, action: #selector(runItem(_:)), keyEquivalent: "")
        item.target = self
        item.image = command.image
        item.representedObject = command
        commandItems.append(item)
        return item
    }

    private func updateShortcutLabels() {
        for item in commandItems {
            guard let command = item.representedObject as? HyperCommand else { continue }
            if let label = keymap.label(for: command) {
                shortcuts[ObjectIdentifier(item)] = (command.title, label, true)
            } else {
                shortcuts[ObjectIdentifier(item)] = nil
                item.attributedTitle = nil
            }
        }
        if let menu = statusItem.menu { alignShortcuts(in: menu) }
    }

    /// Lists the app shortcuts, ⇪ ones first, each layer by app name. Rebuilt whenever the menu
    /// opens, so it also picks up apps installed or moved since.
    private func updateApps() {
        guard let menu = statusItem.menu else { return }
        for item in appItems {
            menu.removeItem(item)
            shortcuts[ObjectIdentifier(item)] = nil
        }
        appItems = []
        appNotes = []
        for layer in HyperLayer.allCases {
            let apps = (keymap.layers[layer] ?? [:]).compactMap { key, command -> (String, Int, HyperCommand)? in
                guard case .launch(let bundleID) = command else { return nil }
                if AppLauncher.url(for: bundleID) == nil, let name = Keyboard.names[key] {
                    appNotes.append("\(layer.symbol)\(name): no app with bundle ID \(bundleID)")
                }
                return (command.title, key, command)
            }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            for (title, key, command) in apps {
                let icon = command.image
                icon?.size = NSSize(width: 16, height: 16)
                let item = shortcutItem(title, Keyboard.names[key].map { layer.symbol + $0 }, #selector(runItem(_:)),
                                        image: icon)
                item.representedObject = command
                appItems.append(item)
            }
        }
        let start = menu.index(of: appsHeader) + 1
        for (offset, item) in appItems.enumerated() { menu.insertItem(item, at: start + offset) }
        appsSeparator.isHidden = appItems.isEmpty
        appsHeader.isHidden = appItems.isEmpty
    }

    private func shortcutItem(_ title: String, _ label: String?, _ action: Selector,
                              image: NSImage? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = image
        if let label { shortcuts[ObjectIdentifier(item)] = (title, label, image != nil) }
        return item
    }

    // Key equivalents only accept real modifiers (⌃⌥⇧⌘), so the ⇪ shortcut is drawn into the
    // title. Like a native shortcut column, labels are right-aligned on a grid of equal cells, one
    // symbol per cell, so the key, ⇪ and ⌥ each line up. The grid ends past the widest visible
    // item, at the menu's right edge (left of the arrow column when the menu has a submenu).
    private func alignShortcuts(in menu: NSMenu) {
        let font = NSFont.menuFont(ofSize: 0)
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let visible = menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }
        let labelled = visible.compactMap { item in shortcuts[ObjectIdentifier(item)].map { (item, $0) } }
        let others = visible.filter { shortcuts[ObjectIdentifier($0)] == nil }
        let titleWidth = labelled.map { width($0.1.title) }.max() ?? 0
        let otherWidth = others.map { width($0.title) }.max() ?? 0
        let symbols = labelled.map { Array($0.1.label) }
        let cell = ceil(symbols.joined().map { width(String($0)) }.max() ?? 0) + 2
        let columns = CGFloat(symbols.map(\.count).max() ?? 0)
        let edge = ceil(max(titleWidth + 24 + columns * cell, otherWidth))
        let hasIcons = labelled.contains { $0.1.icon }

        for ((item, shortcut), symbols) in zip(labelled, symbols) {
            // Tab stops count from the title, and an icon pushes the title right. A row without
            // one (Settings…, Quit) starts that much further left, so its stops move right to match.
            let rowEdge = hasIcons && !shortcut.icon ? edge + Self.iconColumnWidth : edge
            // A row only gets the rightmost stops it fills, so its first tab lands in the right cell.
            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = symbols.indices.map { index in
                let fromRight = CGFloat(symbols.count - index) - 0.5
                return NSTextTab(textAlignment: .center, location: rowEdge - fromRight * cell)
            }
            let title = NSMutableAttributedString(string: shortcut.title,
                                                  attributes: [.font: font, .paragraphStyle: paragraph])
            title.append(NSAttributedString(string: symbols.map { "\t\($0)" }.joined(), attributes: [
                .font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            item.attributedTitle = title
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Opening the menu is the natural next step when shortcuts stop working.
        hyperKey.recheck()
        updateApps()
        let trusted = WindowMover.isTrusted
        permissionItem.isHidden = trusted

        var notes: [String] = []
        if !trusted { notes.append("Accessibility access is off") }

        switch hyperKey.state {
        case .waitingForAccessibility: notes.append("⇪ shortcuts start once Accessibility access is on")
        case .failed(let reason): notes.append("⇪ shortcuts are off: \(reason). Relaunch Caplet to retry")
        case .takenOver(let key):
            notes.append("⇪ shortcuts are off: another app remapped Caps Lock" + (key.map { " to \($0)" } ?? ""))
        case .off, .active: break
        }
        if case .takenOver = hyperKey.state { takeBackItem.isHidden = false } else { takeBackItem.isHidden = true }

        notes += appNotes

        statusLine.title = notes.joined(separator: " · ")
        statusLine.isHidden = notes.isEmpty
        alignShortcuts(in: menu)

        // Window commands need Accessibility access; opening apps doesn't.
        for item in commandItems { item.isEnabled = trusted }
    }

    @objc private func runItem(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? HyperCommand else { return }
        run(command)
    }

    private func run(_ command: HyperCommand) {
        do {
            switch command {
            case .tile(let action): try WindowMover.perform(action, cycling: cyclingEnabled)
            case .arrange(let action): try WindowMover.arrange(action)
            case .launch(let bundleID): try AppLauncher.toggle(bundleID)
            }
        } catch TileError.notTrusted {
            WindowMover.requestTrust()
        } catch {
            NSSound.beep()
            NSLog("Caplet: %@ failed: %@", String(describing: command), String(describing: error))
        }
    }

    @objc private func takeBackCapsLock() {
        hyperKey.takeBack()
    }

    @objc private func openAccessibilitySettings() {
        WindowMover.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
