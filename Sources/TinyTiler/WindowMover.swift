import AppKit
import ApplicationServices
import TilerCore

enum TileError: Error, CustomStringConvertible {
    case notTrusted
    case noFocusedWindow
    case fullScreen
    case noScreens
    case singleDisplay
    case axFailure(AXError)

    var description: String {
        switch self {
        case .notTrusted: return "TinyTiler needs Accessibility access."
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

    static func perform(_ action: TileAction) throws {
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

        guard let primaryHeight = NSScreen.screens.first?.frame.height else { throw TileError.noScreens }
        let screens = NSScreen.screens.map { Layout.flip($0.visibleFrame, primaryHeight: primaryHeight) }
        guard let index = Layout.screenIndex(for: current, in: screens) else { throw TileError.noScreens }

        let target: CGRect
        if let single = Layout.frame(for: action, in: screens[index]) {
            target = single
        } else {
            guard screens.count > 1 else { throw TileError.singleDisplay }
            target = Layout.move(current, from: screens[index], to: screens[(index + 1) % screens.count])
        }

        try withEnhancedUIDisabled(appElement) {
            try setFrame(of: window, to: target)
        }
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

    private static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }
}
