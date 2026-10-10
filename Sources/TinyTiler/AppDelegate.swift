import AppKit
import TilerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private lazy var hyperKey = HyperKeyController { [weak self] action in self?.run(action) }

    private let permissionItem = NSMenuItem(title: "Grant Accessibility Access…",
                                            action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let cycleItem = NSMenuItem(title: "Cycle Sizes on Repeated Presses",
                                       action: #selector(toggleCycling), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin),
                                       keyEquivalent: "")
    private var loginItemError: String?
    private var terminationSignal: DispatchSourceSignal?

    private static let cyclingKey = "cycleSizes"

    private var cyclingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.cyclingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.cyclingKey) }
    }

    private static func shortcutLabel(for action: TileAction) -> String? {
        HyperBindings.keyLabels[action].map { "⇪\($0)" }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1",
                                           accessibilityDescription: "TinyTiler")
        statusItem.menu = buildMenu()

        WindowMover.requestTrust()
        hyperKey.start()
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

    func applicationWillTerminate(_ notification: Notification) {
        hyperKey.stop()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let paragraph = shortcutParagraphStyle()
        for action in TileAction.allCases {
            if action == .topLeft || action == .maximize { menu.addItem(.separator()) }
            let item = NSMenuItem(title: action.title, action: #selector(menuAction(_:)), keyEquivalent: "")
            item.attributedTitle = titleWithShortcut(for: action, paragraph: paragraph)
            item.representedObject = action.rawValue
            item.target = self
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
        permissionItem.target = self
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TinyTiler", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    // Key equivalents only accept real modifiers (⌃⌥⇧⌘), so the ⇪ shortcut is drawn into the
    // title after a right-aligned tab stop, styled like a native shortcut column.
    private func shortcutParagraphStyle() -> NSParagraphStyle {
        let font = NSFont.menuFont(ofSize: 0)
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let titleWidth = TileAction.allCases.map { width($0.title) }.max() ?? 0
        let labelWidth = TileAction.allCases.compactMap(Self.shortcutLabel(for:)).map(width).max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: ceil(titleWidth + 48 + labelWidth))]
        return paragraph
    }

    private func titleWithShortcut(for action: TileAction, paragraph: NSParagraphStyle) -> NSAttributedString? {
        guard let label = Self.shortcutLabel(for: action) else { return nil }
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(string: action.title + "\t",
                                              attributes: [.font: font, .paragraphStyle: paragraph])
        title.append(NSAttributedString(string: label, attributes: [
            .font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return title
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let trusted = WindowMover.isTrusted
        permissionItem.isHidden = trusted
        cycleItem.state = cyclingEnabled ? .on : .off

        var notes: [String] = []
        if !trusted { notes.append("Accessibility access is off") }

        switch hyperKey.state {
        case .waitingForAccessibility: notes.append("⇪ shortcuts start once Accessibility access is on")
        case .failed(let reason): notes.append("⇪ shortcuts are off: \(reason). Relaunch TinyTiler to retry")
        case .off, .active: break
        }

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
        if login == .unavailable { notes.append("Launch at login needs TinyTiler.app, not swift run") }
        if let loginItemError { notes.append(loginItemError) }

        statusLine.title = notes.joined(separator: " · ")
        statusLine.isHidden = notes.isEmpty

        for item in menu.items {
            if item.representedObject is String { item.isEnabled = trusted }
        }
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = TileAction(rawValue: raw) else { return }
        run(action)
    }

    private func run(_ action: TileAction) {
        do {
            try WindowMover.perform(action, cycling: cyclingEnabled)
        } catch TileError.notTrusted {
            WindowMover.requestTrust()
        } catch {
            NSSound.beep()
            NSLog("TinyTiler: %@ failed: %@", action.title, String(describing: error))
        }
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
            NSLog("TinyTiler: %@", String(describing: error))
        }
    }

    @objc private func openAccessibilitySettings() {
        WindowMover.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
