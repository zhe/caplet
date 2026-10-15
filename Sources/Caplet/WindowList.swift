import AppKit
import ApplicationServices
import CapletCore

/// Private, but stable for over a decade and used by most window managers: the only way to
/// match an Accessibility window to the window server's list, which knows the stacking order.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

@MainActor
enum WindowList {
    struct App {
        let element: AXUIElement
        let windows: [CGWindowID: AXUIElement]
    }

    /// Windows on the current Space, front to back. Minimized windows and hidden apps are
    /// not on screen, so they never show up. Bounds and owner need no Screen Recording access.
    static func frontToBack() -> [WindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return entries.compactMap { entry in
            guard let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return WindowSnapshot(id: id, pid: pid, frame: frame,
                                  layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                                  alpha: (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        }
    }

    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success ? id : nil
    }

    /// The app's standard windows (no dialogs, sheets or panels), keyed by window ID.
    static func app(pid: pid_t) -> App {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 1.0)
        let all: [AXUIElement] = WindowMover.copyAttribute(element, kAXWindowsAttribute) ?? []
        var windows: [CGWindowID: AXUIElement] = [:]
        for window in all {
            let subrole: String? = WindowMover.copyAttribute(window, kAXSubroleAttribute)
            guard subrole == kAXStandardWindowSubrole as String, let id = windowID(of: window) else { continue }
            AXUIElementSetMessagingTimeout(window, 1.0)
            windows[id] = window
        }
        return App(element: element, windows: windows)
    }
}
