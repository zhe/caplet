import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum TileAction: String, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case maximize
    case nextDisplay

    public var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .maximize: return "Maximize"
        case .nextDisplay: return "Next Display"
        }
    }
}

/// Pure geometry. Every rect here is in Accessibility coordinates:
/// origin at the top-left of the primary display, y growing downward.
public enum Layout {
    /// Converts between Cocoa screen coordinates (bottom-left origin, y up) and
    /// Accessibility coordinates. The transform is its own inverse.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Target frame for a single-screen action inside `visible` (the screen's visible frame).
    /// `fraction` is the share of the screen width used by `.leftHalf` / `.rightHalf`.
    /// Returns nil for `.nextDisplay`, which needs a destination screen; use `move(_:from:to:)`.
    public static func frame(for action: TileAction, in visible: CGRect, fraction: CGFloat = 1.0 / 2) -> CGRect? {
        switch action {
        case .leftHalf:
            let width = (visible.width * fraction).rounded(.down)
            return CGRect(x: visible.minX, y: visible.minY, width: width, height: visible.height)
        case .rightHalf:
            // Complement of the left frame with fraction (1 - f), so left ⅓ + right ⅔ tile exactly.
            let width = visible.width - (visible.width * (1 - fraction)).rounded(.down)
            return CGRect(x: visible.maxX - width, y: visible.minY, width: width, height: visible.height)
        case .maximize:
            return visible
        case .nextDisplay:
            return nil
        }
    }

    /// Index of the screen that overlaps `window` the most, falling back to the nearest screen
    /// when the window is entirely off-screen.
    public static func screenIndex(for window: CGRect, in screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let overlaps = screens.map { screen -> CGFloat in
            let i = screen.intersection(window)
            return i.isNull ? 0 : i.width * i.height
        }
        if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 {
            return best
        }
        let center = CGPoint(x: window.midX, y: window.midY)
        return screens.indices.min(by: {
            distanceSquared(center, screens[$0]) < distanceSquared(center, screens[$1])
        })
    }

    /// Moves `window` from one screen to another, keeping its position and size proportional
    /// to the screen so a left-half window stays a left-half window.
    public static func move(_ window: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return window }
        let sx = destination.width / source.width
        let sy = destination.height / source.height
        let moved = CGRect(
            x: (destination.minX + (window.minX - source.minX) * sx).rounded(),
            y: (destination.minY + (window.minY - source.minY) * sy).rounded(),
            width: (window.width * sx).rounded(),
            height: (window.height * sy).rounded()
        )
        return clamp(moved, to: destination)
    }

    /// Shrinks and shifts `rect` so it lies entirely inside `bounds`.
    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private static func distanceSquared(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
