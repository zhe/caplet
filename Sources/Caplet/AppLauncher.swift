import AppKit

/// Opens apps for the ⇪ app shortcuts.
@MainActor
enum AppLauncher {
    struct NotInstalled: Error, CustomStringConvertible {
        var bundleID: String
        var description: String { "No app with bundle ID \(bundleID) is installed." }
    }

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// The app's name as Finder shows it, or the bundle ID when it isn't installed.
    static func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else { return bundleID }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// When the app is in front, tiles its windows if it has several that aren't tiled yet,
    /// and hides it otherwise. When it isn't, opens it, or brings it forward when it's running.
    /// Opening a running app also unhides it and, like clicking it in the Dock, opens a window
    /// if it has none.
    static func toggle(_ bundleID: String) throws {
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundleID {
            if !WindowMover.tileAppWindows() { front.hide() }
            return
        }
        guard let url = url(for: bundleID) else { throw NotInstalled(bundleID: bundleID) }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            Task { @MainActor in
                NSSound.beep()
                NSLog("Caplet: opening %@ failed: %@", bundleID, String(describing: error))
            }
        }
    }
}
