import AppKit
import CapletCore

/// Titles and icons of ⇪ commands, shared by the menu and the Settings keyboard.
@MainActor
extension HyperCommand {
    var title: String {
        switch self {
        case .tile(let action): return action.title
        case .arrange(let action): return action.title
        case .launch(let bundleID): return AppLauncher.name(for: bundleID)
        }
    }

    /// An SF Symbol for window commands, the app's icon for app commands.
    var image: NSImage? {
        switch self {
        case .tile(let action): return Self.symbol(Self.symbolNames(for: action), title)
        case .arrange(let action): return Self.symbol(Self.symbolNames(for: action), title)
        case .launch(let bundleID):
            return AppLauncher.url(for: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
                ?? NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: title)
        }
    }

    /// SF Symbols matching the system Window › Move & Resize menu. Those `inset.filled.*`
    /// names arrived in macOS 15, so each entry carries an older look-alike for macOS 13–14.
    private static func symbolNames(for action: TileAction) -> (String, fallback: String) {
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

    private static func symbolNames(for action: ArrangeAction) -> (String, fallback: String) {
        switch action {
        case .leftAndRight: return ("inset.filled.lefthalf.righthalf.rectangle", "rectangle.split.2x1")
        case .rightAndLeft: return ("inset.filled.righthalf.lefthalf.rectangle", "rectangle.split.2x1")
        case .topAndBottom: return ("inset.filled.tophalf.bottomhalf.rectangle", "rectangle.split.1x2")
        case .bottomAndTop: return ("inset.filled.bottomhalf.tophalf.rectangle", "rectangle.split.1x2")
        case .quartersFromTopLeft, .quartersFromTopRight, .quartersFromBottomLeft, .quartersFromBottomRight:
            return ("inset.filled.topleft.topright.bottomleft.bottomright.rectangle", "rectangle.split.2x2")
        }
    }

    private static func symbol(_ names: (String, fallback: String), _ title: String) -> NSImage? {
        NSImage(systemSymbolName: names.0, accessibilityDescription: title)
            ?? NSImage(systemSymbolName: names.fallback, accessibilityDescription: title)
    }
}
