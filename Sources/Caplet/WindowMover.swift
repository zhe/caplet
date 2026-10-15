import AppKit
import ApplicationServices
import CapletCore

enum TileError: Error, CustomStringConvertible {
    case notTrusted
    case noFocusedWindow
    case fullScreen
    case noScreens
    case singleDisplay
    case axFailure(AXError)

    var description: String {
        switch self {
        case .notTrusted: return "Caplet needs Accessibility access."
        case .noFocusedWindow: return "The frontmost app has no focused window."
        case .fullScreen: return "Full-screen windows can't be tiled."
        case .noScreens: return "No displays found."
        case .singleDisplay: return "Only one display is connected."
        case .axFailure(let error): return "Accessibility call failed (\(error.rawValue))."
        }
    }
}

/// Moves other apps' windows through the Accessibility API (AXUIElement).
@MainActor
enum WindowMover {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow Accessibility" prompt if the app is not trusted yet.
    @discardableResult
    static func requestTrust() -> Bool {
        // String literal instead of kAXTrustedCheckOptionPrompt, which is a non-Sendable global.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private static var lastCycle: (window: AXUIElement, record: CycleRecord)?

    static func perform(_ action: TileAction, cycling: Bool) throws {
        guard isTrusted else { throw TileError.notTrusted }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw TileError.noFocusedWindow }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // A hung app would otherwise block the main thread for the default ~6s.
        AXUIElementSetMessagingTimeout(appElement, 1.0)

        guard let window: AXUIElement = copyAttribute(appElement, kAXFocusedWindowAttribute) else {
            throw TileError.noFocusedWindow
        }
        if let fullScreen: Bool = copyAttribute(window, "AXFullScreen"), fullScreen {
            throw TileError.fullScreen
        }
        let current = try frame(of: window)

        let screens = try visibleScreens()
        guard let index = Layout.screenIndex(for: current, in: screens) else { throw TileError.noScreens }

        let screen = screens[index]
        let last = cycling ? lastCycle.flatMap { CFEqual($0.window, window) ? $0.record : nil } : nil
        let step = cycling ? Cycle.nextStep(for: action, window: current, screen: screen, last: last) : 0

        let target: CGRect
        switch action {
        case .maximize:
            target = screen
        case .nextDisplay:
            guard screens.count > 1 else { throw TileError.singleDisplay }
            target = Layout.move(current, from: screen, to: screens[(index + 1) % screens.count])
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf,
             .topLeft, .topRight, .bottomLeft, .bottomRight, .center:
            guard let tiled = Cycle.target(for: action, step: step, window: current, screen: screen) else { return }
            target = tiled
        }

        try withEnhancedUIDisabled(appElement) {
            try setFrame(of: window, to: target)
        }

        if Cycle.supports(action), let achieved = try? frame(of: window) {
            lastCycle = (window, CycleRecord(action: action, step: step, screen: screen, achieved: achieved))
        } else {
            lastCycle = nil
        }
    }

    /// Tiles the focused window into the first slot and the windows right behind it on the
    /// same display into the rest. Nothing is raised, so focus and stacking stay as they were.
    static func arrange(_ action: ArrangeAction) throws {
        guard isTrusted else { throw TileError.notTrusted }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw TileError.noFocusedWindow }
        let pid = app.processIdentifier

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)
        guard let window: AXUIElement = copyAttribute(appElement, kAXFocusedWindowAttribute) else {
            throw TileError.noFocusedWindow
        }
        if let fullScreen: Bool = copyAttribute(window, "AXFullScreen"), fullScreen {
            throw TileError.fullScreen
        }
        let current = try frame(of: window)

        let screens = try visibleScreens()
        guard let index = Layout.screenIndex(for: current, in: screens) else { throw TileError.noScreens }

        let onScreen = WindowList.frontToBack()
        // The frontmost app's top window is the focused one in practice.
        let focusedID = WindowList.windowID(of: window) ?? onScreen.first { $0.pid == pid }?.id ?? 0
        let focused = WindowSnapshot(id: focusedID, pid: pid, frame: current)

        var followers: [(app: AXUIElement, window: AXUIElement)] = []
        var apps: [pid_t: WindowList.App] = [:]
        for candidate in Arrange.followers(of: focused, frontToBack: onScreen, screens: screens,
                                           excludingPID: getpid()) {
            guard followers.count < action.slots.count - 1 else { break }
            let owner = apps[candidate.pid] ?? WindowList.app(pid: candidate.pid)
            apps[candidate.pid] = owner
            if let match = owner.windows[candidate.id] { followers.append((owner.element, match)) }
        }

        let frames = Arrange.frames(for: action, windowCount: followers.count + 1, in: screens[index])
        guard let first = frames.first else { return }
        try withEnhancedUIDisabled(appElement) {
            try setFrame(of: window, to: first)
        }
        for (follower, target) in zip(followers, frames.dropFirst()) {
            do {
                try withEnhancedUIDisabled(follower.app) {
                    try setFrame(of: follower.window, to: target)
                }
            } catch {
                NSLog("Caplet: couldn't arrange a window: %@", String(describing: error))
            }
        }
        lastCycle = nil
    }

    /// Visible frames (without menu bar and Dock) in Accessibility coordinates.
    private static func visibleScreens() throws -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { throw TileError.noScreens }
        return NSScreen.screens.map { Layout.flip($0.visibleFrame, primaryHeight: primaryHeight) }
    }

    private static func frame(of window: AXUIElement) throws -> CGRect {
        guard let position: AXValue = copyAttribute(window, kAXPositionAttribute),
              let size: AXValue = copyAttribute(window, kAXSizeAttribute) else {
            throw TileError.axFailure(.cannotComplete)
        }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position, .cgPoint, &origin)
        AXValueGetValue(size, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    private static func setFrame(of window: AXUIElement, to rect: CGRect) throws {
        var origin = rect.origin
        var extent = rect.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let size = AXValueCreate(.cgSize, &extent) else { return }
        // Size, then position, then size again: when crossing displays the window manager
        // clamps the size against whichever screen the window is on at that moment.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size)
        if result != .success { throw TileError.axFailure(result) }
    }

    /// Apps with AXEnhancedUserInterface on (set by VoiceOver and some assistive tools)
    /// animate every frame change, which makes tiling slow and imprecise.
    private static func withEnhancedUIDisabled(_ app: AXUIElement, _ body: () throws -> Void) rethrows {
        let attribute = "AXEnhancedUserInterface" as CFString
        let wasEnabled: Bool = copyAttribute(app, attribute as String) ?? false
        if wasEnabled { AXUIElementSetAttributeValue(app, attribute, kCFBooleanFalse) }
        defer { if wasEnabled { AXUIElementSetAttributeValue(app, attribute, kCFBooleanTrue) } }
        try body()
    }

    static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }
}
