import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What the previous tile did, so a repeated press can advance to the next width.
public struct CycleRecord: Equatable, Sendable {
    public var action: TileAction
    public var step: Int
    public var screen: CGRect
    /// The frame the app actually accepted, which can differ from the requested one
    /// (Terminal snaps to character cells, some apps enforce minimum sizes).
    public var achieved: CGRect

    public init(action: TileAction, step: Int, screen: CGRect, achieved: CGRect) {
        self.action = action
        self.step = step
        self.screen = screen
        self.achieved = achieved
    }
}

public enum Cycle {
    /// Widths (left/right) or heights (top/bottom) visited by repeated presses, in order.
    public static let fractions: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]

    public static func supports(_ action: TileAction) -> Bool {
        switch action {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return true
        case .maximize, .nextDisplay: return false
        }
    }

    /// Picks the cycle step for this press.
    ///
    /// Advances when the window is still where the previous press of the same action left it,
    /// or when it already sits exactly at one of the cycle frames (for example after a relaunch).
    /// Anything else starts over at ½.
    public static func nextStep(for action: TileAction, window: CGRect, screen: CGRect,
                                last: CycleRecord?) -> Int {
        guard supports(action) else { return 0 }

        if let last, last.action == action, last.screen == screen,
           Layout.approximatelyEqual(last.achieved, window) {
            return (last.step + 1) % fractions.count
        }
        for (step, fraction) in fractions.enumerated() {
            if let frame = Layout.frame(for: action, in: screen, fraction: fraction),
               Layout.approximatelyEqual(frame, window) {
                return (step + 1) % fractions.count
            }
        }
        return 0
    }
}
