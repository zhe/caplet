import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What the previous tile did, so a repeated press can advance to the next size.
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
    /// Widths (left/right, corners) or heights (top/bottom) visited by repeated presses, in order.
    public static let fractions: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]

    /// Share of the screen's width and height used from the second press of `.center` on.
    public static let centerFraction: CGFloat = 2.0 / 3

    public static func stepCount(for action: TileAction) -> Int {
        switch action {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf,
             .topLeft, .topRight, .bottomLeft, .bottomRight: return fractions.count
        case .center: return 2 // own size, then ⅔ of the screen
        case .maximize, .nextDisplay: return 1
        }
    }

    public static func supports(_ action: TileAction) -> Bool {
        stepCount(for: action) > 1
    }

    /// Halves and corners loop back to the first size; center stops at its last step.
    public static func wraps(_ action: TileAction) -> Bool {
        action != .center
    }

    /// Picks the step for this press.
    ///
    /// Advances when the window is still where the previous press of the same action left it,
    /// or when it already sits exactly at one of the step frames (for example after a relaunch).
    /// Anything else starts over at step 0.
    public static func nextStep(for action: TileAction, window: CGRect, screen: CGRect,
                                last: CycleRecord?) -> Int {
        let count = stepCount(for: action)
        guard count > 1 else { return 0 }

        func advance(from step: Int) -> Int {
            wraps(action) ? (step + 1) % count : min(step + 1, count - 1)
        }

        if let last, last.action == action, last.screen == screen,
           Layout.approximatelyEqual(last.achieved, window) {
            return advance(from: last.step)
        }
        for step in 0..<count {
            if let frame = target(for: action, step: step, window: window, screen: screen),
               Layout.approximatelyEqual(frame, window) {
                return advance(from: step)
            }
        }
        return 0
    }

    /// The frame for `step` of a stepping action. Returns nil for actions that don't step.
    public static func target(for action: TileAction, step: Int, window: CGRect, screen: CGRect) -> CGRect? {
        switch action {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf,
             .topLeft, .topRight, .bottomLeft, .bottomRight:
            return Layout.frame(for: action, in: screen, fraction: fractions[step % fractions.count])
        case .center:
            guard step > 0 else { return Layout.centered(window, in: screen) }
            let size = CGSize(width: (screen.width * centerFraction).rounded(.down),
                              height: (screen.height * centerFraction).rounded(.down))
            return Layout.centered(CGRect(origin: window.origin, size: size), in: screen)
        case .maximize, .nextDisplay:
            return nil
        }
    }
}
