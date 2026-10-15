import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Tiles the focused window and the windows right behind it in one go.
public enum ArrangeAction: String, CaseIterable, Sendable {
    case leftAndRight
    case rightAndLeft
    case topAndBottom
    case bottomAndTop
    case quartersFromTopLeft
    case quartersFromTopRight
    case quartersFromBottomLeft
    case quartersFromBottomRight

    /// The variants listed in the menu; the other quarter variants are shortcut-only.
    public static let menuCases: [ArrangeAction] = [
        .leftAndRight, .rightAndLeft, .topAndBottom, .bottomAndTop, .quartersFromTopLeft,
    ]

    public var title: String {
        switch self {
        case .leftAndRight: return "Left & Right"
        case .rightAndLeft: return "Right & Left"
        case .topAndBottom: return "Top & Bottom"
        case .bottomAndTop: return "Bottom & Top"
        case .quartersFromTopLeft: return "Quarters"
        case .quartersFromTopRight: return "Quarters from Top Right"
        case .quartersFromBottomLeft: return "Quarters from Bottom Left"
        case .quartersFromBottomRight: return "Quarters from Bottom Right"
        }
    }

    /// Where the focused window goes, then the next window, and so on.
    public var slots: [TileAction] {
        switch self {
        case .leftAndRight: return [.leftHalf, .rightHalf]
        case .rightAndLeft: return [.rightHalf, .leftHalf]
        case .topAndBottom: return [.topHalf, .bottomHalf]
        case .bottomAndTop: return [.bottomHalf, .topHalf]
        case .quartersFromTopLeft: return Self.quarters(startingAt: .topLeft)
        case .quartersFromTopRight: return Self.quarters(startingAt: .topRight)
        case .quartersFromBottomLeft: return Self.quarters(startingAt: .bottomLeft)
        case .quartersFromBottomRight: return Self.quarters(startingAt: .bottomRight)
        }
    }

    private static func quarters(startingAt first: TileAction) -> [TileAction] {
        [first] + [TileAction.topLeft, .topRight, .bottomLeft, .bottomRight].filter { $0 != first }
    }
}

/// An on-screen window as reported by the window server, in Accessibility coordinates.
public struct WindowSnapshot: Equatable, Sendable {
    public var id: UInt32
    public var pid: Int32
    public var frame: CGRect
    /// 0 for normal app windows; menus, panels, the Dock and the menu bar sit on other layers.
    public var layer: Int
    public var alpha: Double

    public init(id: UInt32, pid: Int32, frame: CGRect, layer: Int = 0, alpha: Double = 1) {
        self.id = id
        self.pid = pid
        self.frame = frame
        self.layer = layer
        self.alpha = alpha
    }
}

public enum Arrange {
    /// Smaller windows are treated as palettes or popovers and left alone.
    public static let minimumSize = CGSize(width: 120, height: 80)

    /// Windows that can join the focused one, front to back: normal, visible windows that sit
    /// mostly on the focused window's display.
    public static func followers(of focused: WindowSnapshot, frontToBack windows: [WindowSnapshot],
                                 screens: [CGRect], excludingPID: Int32) -> [WindowSnapshot] {
        guard let display = Layout.screenIndex(for: focused.frame, in: screens) else { return [] }
        return windows.filter { window in
            window.id != focused.id
                && window.pid != excludingPID
                && window.layer == 0
                && window.alpha > 0
                && window.frame.width >= minimumSize.width
                && window.frame.height >= minimumSize.height
                && Layout.screenIndex(for: window.frame, in: screens) == display
        }
    }

    /// Target frames for the first `windowCount` slots. With fewer windows than slots,
    /// the remaining slots stay empty.
    public static func frames(for action: ArrangeAction, windowCount: Int, in screen: CGRect) -> [CGRect] {
        action.slots.prefix(max(windowCount, 0)).compactMap { Layout.frame(for: $0, in: screen) }
    }
}
