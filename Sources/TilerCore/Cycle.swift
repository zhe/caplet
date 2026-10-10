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
    /// For `.center`: the window's own size, which the press after ⅔ goes back to.
    public var restoreSize: CGSize?

    public init(action: TileAction, step: Int, screen: CGRect, achieved: CGRect, restoreSize: CGSize? = nil) {
        self.action = action
        self.step = step
        self.screen = screen
        self.achieved = achieved
        self.restoreSize = restoreSize
    }
}

public enum Cycle {
    /// Widths (left/right) or heights (top/bottom) visited by repeated presses, in order.
    public static let fractions: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]

    /// Share of the screen's width and height used by the second press of `.center`.
    public static let centerFraction: CGFloat = 2.0 / 3

    public static func stepCount(for action: TileAction) -> Int {
        switch action {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return fractions.count
        case .center: return 2 // own size, then ⅔ of the screen
        case .maximize, .nextDisplay: return 1
        }
    }

    public static func supports(_ action: TileAction) -> Bool {
        stepCount(for: action) > 1
    }

    /// Picks the cycle step for this press.
    ///
    /// Advances when the window is still where the previous press of the same action left it,
    /// or when it already sits exactly at one of the cycle frames (for example after a relaunch).
    /// Anything else starts over at step 0.
    public static func nextStep(for action: TileAction, window: CGRect, screen: CGRect,
                                last: CycleRecord?) -> Int {
        let count = stepCount(for: action)
        guard count > 1 else { return 0 }

        if let last = matching(last, action: action, window: window, screen: screen) {
            return (last.step + 1) % count
        }
        for step in 0..<count {
            if let frame = target(for: action, step: step, window: window, screen: screen, last: nil)?.frame,
               Layout.approximatelyEqual(frame, window) {
                return (step + 1) % count
            }
        }
        return 0
    }

    /// The frame for `step` of a cycling action, plus the size `.center` should remember.
    /// Returns nil for actions that don't cycle.
    public static func target(for action: TileAction, step: Int, window: CGRect, screen: CGRect,
                              last: CycleRecord?) -> (frame: CGRect, restoreSize: CGSize?)? {
        switch action {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf:
            return Layout.frame(for: action, in: screen, fraction: fractions[step % fractions.count])
                .map { ($0, nil) }
        case .center:
            if step == 1 {
                let size = CGSize(width: (screen.width * centerFraction).rounded(.down),
                                  height: (screen.height * centerFraction).rounded(.down))
                // The window is still at its own size here (step 0 only centered it).
                return (Layout.centered(CGRect(origin: window.origin, size: size), in: screen), window.size)
            }
            let previous = matching(last, action: action, window: window, screen: screen)
            let size = previous?.step == 1 ? previous?.restoreSize ?? window.size : window.size
            return (Layout.centered(CGRect(origin: window.origin, size: size), in: screen), size)
        case .maximize, .nextDisplay:
            return nil
        }
    }

    private static func matching(_ last: CycleRecord?, action: TileAction, window: CGRect,
                                 screen: CGRect) -> CycleRecord? {
        guard let last, last.action == action, last.screen == screen,
              Layout.approximatelyEqual(last.achieved, window) else { return nil }
        return last
    }
}
