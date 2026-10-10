import AppKit
import Carbon.HIToolbox
import TilerCore

struct Shortcut {
    let keyCode: Int
    let carbonModifiers: Int
    let keyEquivalent: String
    let modifierFlags: NSEvent.ModifierFlags

    static func shortcut(for action: TileAction) -> Shortcut {
        let ctrlOpt = controlKey | optionKey
        switch action {
        case .leftHalf:
            return Shortcut(keyCode: kVK_LeftArrow, carbonModifiers: ctrlOpt,
                            keyEquivalent: arrow(NSLeftArrowFunctionKey), modifierFlags: [.control, .option])
        case .rightHalf:
            return Shortcut(keyCode: kVK_RightArrow, carbonModifiers: ctrlOpt,
                            keyEquivalent: arrow(NSRightArrowFunctionKey), modifierFlags: [.control, .option])
        case .maximize:
            return Shortcut(keyCode: kVK_Return, carbonModifiers: ctrlOpt,
                            keyEquivalent: "\r", modifierFlags: [.control, .option])
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
    private var unavailableShortcuts: Set<TileAction> = []
    private let permissionItem = NSMenuItem(title: "Grant Accessibility Access…",
                                            action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

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

        var notes: [String] = []
        if !trusted { notes.append("Accessibility access is off") }
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
            try WindowMover.perform(action)
        } catch TileError.notTrusted {
            WindowMover.requestTrust()
        } catch {
            NSSound.beep()
            NSLog("TinyTiler: %@ failed: %@", action.title, String(describing: error))
        }
    }

    @objc private func openAccessibilitySettings() {
        WindowMover.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
