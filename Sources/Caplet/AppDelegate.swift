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
    private let cycleItem = NSMenuItem(title: "Cycle Sizes on Repeated Presses",
                                       action: #selector(toggleCycling), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin),
                                       keyEquivalent: "")
    private var loginItemError: String?
    /// Plain title and drawn shortcut label of each item that shows one, and whether Caplet gave
    /// it an icon. `NSMenuItem.image` can't tell: macOS 26 returns a default image for Quit
    /// (`terminate:`) that the status menu doesn't draw.
    private var shortcuts: [ObjectIdentifier: (title: String, label: String, icon: Bool)] = [:]
    private var terminationSignal: DispatchSourceSignal?

    private static let cyclingKey = "cycleSizes"
    /// How far a menu item's icon pushes its title right. AppKit doesn't expose this, so it's
    /// measured from the menu on macOS 26: titles with icons start 26pt right of those without.
    private static let iconColumnWidth: CGFloat = 26

    private var cyclingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.cyclingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.cyclingKey) }
    }

    private static func shortcutLabel(for action: TileAction) -> String? {
        HyperBindings.keyLabels[action].map { "⇪\($0)" }
    }

    private static func shortcutLabel(for action: ArrangeAction) -> String? {
        HyperBindings.keyLabel(for: action).map { "⌥⇪\($0)" }
    }

    /// SF Symbols matching the system Window › Move & Resize menu. Those `inset.filled.*`
    /// names arrived in macOS 15, so each entry carries an older look-alike for macOS 13–14.
    private static func symbol(for action: TileAction) -> (String, fallback: String) {
        switch action {
        case .leftHalf: return ("inset.filled.lefthalf.rectangle", "rectangle.lefthalf.inset.filled")
        case .rightHalf: return ("inset.filled.righthalf.rectangle", "rectangle.righthalf.inset.filled")
        case .topHalf: return ("inset.filled.tophalf.rectangle", "rectangle.tophalf.inset.filled")
        case .bottomHalf: return ("inset.filled.bottomhalf.rectangle", "rectangle.bottomhalf.inset.filled")
        case .topLeft: return ("inset.filled.topleft.rectangle", "rectangle.inset.topleft.filled")
        case .topRight: return ("inset.filled.topright.rectangle", "rectangle.inset.topright.filled")
        case .bottomLeft: return ("inset.filled.bottomleft.rectangle", "rectangle.inset.bottomleft.filled")
        case .bottomRight: return ("inset.filled.bottomright.rectangle", "rectangle.inset.bottomright.filled")
        case .maximize: return ("inset.filled.rectangle", "rectangle.inset.filled")
        case .center: return ("inset.filled.center.rectangle", "rectangle.center.inset.filled")
        case .nextDisplay: return ("display.2", "display.2")
        }
    }

    private static func symbol(for action: ArrangeAction) -> (String, fallback: String) {
        switch action {
        case .leftAndRight: return ("inset.filled.lefthalf.righthalf.rectangle", "rectangle.split.2x1")
        case .rightAndLeft: return ("inset.filled.righthalf.lefthalf.rectangle", "rectangle.split.2x1")
        case .topAndBottom: return ("inset.filled.tophalf.bottomhalf.rectangle", "rectangle.split.1x2")
        case .bottomAndTop: return ("inset.filled.bottomhalf.tophalf.rectangle", "rectangle.split.1x2")
        case .quartersFromTopLeft, .quartersFromTopRight, .quartersFromBottomLeft, .quartersFromBottomRight:
            return ("inset.filled.topleft.topright.bottomleft.bottomright.rectangle", "rectangle.split.2x2")
        }
    }

    private static func image(_ symbol: (String, fallback: String), _ title: String) -> NSImage? {
        NSImage(systemSymbolName: symbol.0, accessibilityDescription: title)
            ?? NSImage(systemSymbolName: symbol.fallback, accessibilityDescription: title)
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
            let item = shortcutItem(action.title, Self.shortcutLabel(for: action), #selector(menuAction(_:)),
                                    image: Self.image(Self.symbol(for: action), action.title))
            item.representedObject = action.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Arrange"))
        for action in ArrangeAction.menuCases {
            let item = shortcutItem(action.title, Self.shortcutLabel(for: action), #selector(arrangeAction(_:)),
                                    image: Self.image(Self.symbol(for: action), action.title))
            item.representedObject = action.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())
        cycleItem.target = self
        menu.addItem(cycleItem)
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        statusLine.isEnabled = false
        statusLine.isHidden = true
        menu.addItem(statusLine)
        takeBackItem.target = self
        menu.addItem(takeBackItem)
        permissionItem.target = self
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        let quit = shortcutItem("Quit Caplet", "⌘Q", #selector(NSApplication.terminate(_:)))
        quit.target = NSApp
        menu.addItem(quit)
        // AppKit draws real key equivalents in a column right of every title, which the drawn
        // ⇪ labels can't line up with. This hidden twin keeps ⌘Q working while the menu is open.
        let quitKey = NSMenuItem(title: "Quit Caplet", action: #selector(NSApplication.terminate(_:)),
                                 keyEquivalent: "q")
        quitKey.isHidden = true
        quitKey.allowsKeyEquivalentWhenHidden = true
        menu.addItem(quitKey)

        alignShortcuts(in: menu)
        return menu
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
    // item, at the menu's right edge.
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
        let edge = ceil(max(titleWidth + 48 + columns * cell, otherWidth))
        let hasIcons = labelled.contains { $0.1.icon }

        for ((item, shortcut), symbols) in zip(labelled, symbols) {
            // Tab stops count from the title, and an icon pushes the title right. A row without
            // one (Quit) starts that much further left, so its stops move right to compensate.
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

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) { return .sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Opening the menu is the natural next step when shortcuts stop working.
        hyperKey.recheck()
        let trusted = WindowMover.isTrusted
        permissionItem.isHidden = trusted
        cycleItem.state = cyclingEnabled ? .on : .off

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

        let login = LoginItem.state
        loginItem.isEnabled = login != .unavailable
        switch login {
        case .enabled: loginItem.state = .on
        case .requiresApproval: loginItem.state = .mixed
        case .disabled, .unavailable: loginItem.state = .off
        }
        if login == .requiresApproval {
            notes.append("Launch at login is switched off in System Settings › Login Items")
        }
        if login == .unavailable { notes.append("Launch at login needs Caplet.app, not swift run") }
        if let loginItemError { notes.append(loginItemError) }

        statusLine.title = notes.joined(separator: " · ")
        statusLine.isHidden = notes.isEmpty
        alignShortcuts(in: menu)

        for item in menu.items {
            if item.representedObject is String { item.isEnabled = trusted }
        }
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = TileAction(rawValue: raw) else { return }
        run(.tile(action))
    }

    @objc private func arrangeAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = ArrangeAction(rawValue: raw) else { return }
        run(.arrange(action))
    }

    private func run(_ command: HyperCommand) {
        do {
            switch command {
            case .tile(let action): try WindowMover.perform(action, cycling: cyclingEnabled)
            case .arrange(let action): try WindowMover.arrange(action)
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

    @objc private func toggleCycling() {
        cyclingEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        switch LoginItem.state {
        case .requiresApproval:
            // Registering again won't help; only the user can flip it back on.
            LoginItem.openSystemSettings()
        case .enabled:
            setLaunchAtLogin(false)
        case .disabled:
            setLaunchAtLogin(true)
        case .unavailable:
            break
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't change launch at login: \(error.localizedDescription)"
            NSSound.beep()
            NSLog("Caplet: %@", String(describing: error))
        }
    }

    @objc private func openAccessibilitySettings() {
        WindowMover.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
