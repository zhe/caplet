import Foundation

/// Tells a tap of the ⇪ key (toggle capitals) apart from holding it for a shortcut.
///
/// A press is a tap when no other key went down while ⇪ was held and it was released within
/// `maxTapDuration`. Holding ⇪ and letting go without pressing anything does nothing, so
/// changing your mind mid-shortcut doesn't flip capitals.
public struct CapsTap: Sendable {
    public static let maxTapDuration: TimeInterval = 0.5

    private var pressedAt: TimeInterval?
    private var interrupted = false

    public init() {}

    public var isHeld: Bool { pressedAt != nil }

    /// Key-down of the ⇪ key. Auto-repeats while held are ignored.
    public mutating func pressed(at time: TimeInterval) {
        guard pressedAt == nil else { return }
        pressedAt = time
        interrupted = false
    }

    /// Any other key went down. Only matters while ⇪ is held.
    public mutating func otherKeyPressed() {
        if pressedAt != nil { interrupted = true }
    }

    /// Key-up of the ⇪ key. Returns true when the press was a tap.
    public mutating func released(at time: TimeInterval) -> Bool {
        defer { reset() }
        guard let pressedAt else { return false }
        return !interrupted && time - pressedAt <= Self.maxTapDuration
    }

    public mutating func reset() {
        pressedAt = nil
        interrupted = false
    }
}
