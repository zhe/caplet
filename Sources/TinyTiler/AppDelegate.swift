import AppKit
import Carbon.HIToolbox
import TilerCore

/// Fallback ⌃⌥ shortcuts, registered through Carbon. They work even when the hyper key is off.
struct Shortcut {
    let keyCode: Int
    let carbonModifiers: Int
    let keyEquivalent: String
    let modifierFlags: NSEvent.ModifierFlags

    static func shortcut(for action: TileAction) -> Shortcut {
        let ctrlOpt = controlKey | optionKey
        let flags: NSEvent.ModifierFlags = [.control, .option]
        switch action {
        case .leftHalf:
            return Shortcut(keyCode: kVK_LeftArrow, carbonModifiers: ctrlOpt,
                            keyEquivalent: arrow(NSLeftArrowFunctionKey), modifierFlags: flags)
        case .rightHalf:
            return Shortcut(keyCode: kVK_RightArrow, carbonModifiers: ctrlOpt,
                            keyEquivalent: arrow(NSRightArrowFunctionKey), modifierFlags: flags)
        case .topHalf:
            return Shortcut(keyCode: kVK_UpArrow, carbonModifiers: ctrlOpt,
                            keyEquivalent: arrow(NSUpArrowFunctionKey), modifierFlags: flags)
        case .bottomHalf:
            return Shortcut(keyCode: kVK_DownArrow, carbonModifiers: ctrlOpt,
                            keyEquivalent: arrow(NSDownArrowFunctionKey), modifierFlags: flags)
        case .maximize:
            return Shortcut(keyCode: kVK_Return, carbonModifiers: ctrlOpt,
                            keyEquivalent: "\r", modifierFlags: flags)
        case .center:
            return Shortcut(keyCode: kVK_ANSI_C, carbonModifiers: ctrlOpt,
                            keyEquivalent: "c", modifierFlags: flags)
        case .nextDisplay:
            return Shortcut(keyCode: kVK_RightArrow, carbonModifiers: ctrlOpt | cmdKey,
                            keyEquivalent: arrow(NSRightArrowFunctionKey),
                            modifierFlags: [.control, .option, .command])
        }
    }

    private static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt16(key))!))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyCenter()
    private lazy var hyperKey = HyperKeyController { [weak self] action in self?.run(action) }
    private var unavailableShortcuts: Set<TileAction> = []

    private let permissionItem = NSMenuItem(title: "Grant Accessibility Access…",
                                            action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let cycleItem = NSMenuItem(title: "Cycle Sizes on Repeated Presses",
                                       action: #selector(toggleCycling), keyEquivalent: "")
    private let hyperItem = NSMenuItem(title: "Caps Lock as Hyper Key",
                                       action: #selector(toggleHyperKey), keyEquivalent: "")
    private let hyperHint = NSMenuItem(title: AppDelegate.hyperHintText, action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin),
                                       keyEquivalent: "")
    private var loginItemError: String?
    private var terminationSignal: DispatchSourceSignal?

    private static let cyclingKey = "cycleSizes"
    private static let hyperKeyDefaultsKey = "capsLockHyperKey"

    private var cyclingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.cyclingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.cyclingKey) }
    }

    private var hyperKeyEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.hyperKeyDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.hyperKeyDefaultsKey) }
    }

    private static var hyperHintText: String {
        let keys = HyperBindings.keyLabels
        let wasd = [TileAction.topHalf, .leftHalf, .bottomHalf, .rightHalf].compactMap { keys[$0] }.joined(separator: " ")
        let others: [(TileAction, String)] = [(.maximize, "maximize"), (.center, "center"), (.nextDisplay, "next display")]
        let rest = others.map { "\(keys[$0.0] ?? "") \($0.1)" }.joined(separator: " · ")
        return "Hold Caps Lock + \(wasd) halves · \(rest)"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1",
                                           accessibilityDescription: "TinyTiler")
        statusItem.menu = buildMenu()

        for action in TileAction.allCases {
            let shortcut = Shortcut.shortcut(for: action)
            let ok = hotKeys.register(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) { [weak self] in
                self?.run(action)
            }
            if !ok { unavailableShortcuts.insert(action) }
        }

        WindowMover.requestTrust()
        if hyperKeyEnabled { hyperKey.start() }
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

        for action in TileAction.allCases {
            let shortcut = Shortcut.shortcut(for: action)
            // Key equivalents here are display-only; the global hotkeys do the real work.
            let item = NSMenuItem(title: action.title, action: #selector(menuAction(_:)),
                                  keyEquivalent: shortcut.keyEquivalent)
            item.keyEquivalentModifierMask = shortcut.modifierFlags
            item.representedObject = action.rawValue
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        hyperItem.target = self
        menu.addItem(hyperItem)
        hyperHint.isEnabled = false
        menu.addItem(hyperHint)
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        let trusted = WindowMover.isTrusted
        permissionItem.isHidden = trusted
        cycleItem.state = cyclingEnabled ? .on : .off
        hyperItem.state = hyperKeyEnabled ? .on : .off
        hyperHint.isHidden = hyperKey.state != .active

        var notes: [String] = []
        if !trusted { notes.append("Accessibility access is off") }

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

        switch hyperKey.state {
        case .waitingForAccessibility: notes.append("Hyper key starts once Accessibility access is on")
        case .failed(let reason): notes.append("Hyper key off: \(reason)")
        case .off, .active: break
        }
        if !unavailableShortcuts.isEmpty {
            let names = TileAction.allCases.filter { unavailableShortcuts.contains($0) }.map(\.title)
            notes.append("Shortcut taken by another app: \(names.joined(separator: ", "))")
        }
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

    @objc private func toggleHyperKey() {
        hyperKeyEnabled.toggle()
        if hyperKeyEnabled { hyperKey.start() } else { hyperKey.stop() }
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
