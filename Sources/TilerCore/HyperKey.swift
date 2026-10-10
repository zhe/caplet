import Foundation

/// Keys pressed while the hyper key (Caps Lock) is held, keyed by macOS virtual key code.
/// Virtual key codes follow physical position, so W A S D stay under the left hand on any layout.
public enum HyperBindings {
    /// F18 (kVK_F18). Caps Lock is remapped to it because Caps Lock itself only reports toggles.
    public static let triggerKeyCode = 0x4F

    public static let actions: [Int: TileAction] = [
        0x0D: .topHalf,     // W
        0x00: .leftHalf,    // A
        0x01: .bottomHalf,  // S
        0x02: .rightHalf,   // D
        0x03: .maximize,    // F
        0x0E: .nextDisplay, // E
    ]

    public static let keyLabels: [TileAction: String] = [
        .topHalf: "W", .leftHalf: "A", .bottomHalf: "S", .rightHalf: "D", .maximize: "F", .nextDisplay: "E",
    ]

    public static func action(forKeyCode keyCode: Int) -> TileAction? {
        actions[keyCode]
    }
}

/// One entry of hidutil's `UserKeyMapping` (HID usage page << 32 | usage).
public struct KeyMapping: Equatable, Sendable {
    public var src: UInt64
    public var dst: UInt64

    public init(src: UInt64, dst: UInt64) {
        self.src = src
        self.dst = dst
    }
}

/// Builds `hidutil property` arguments that remap Caps Lock to F18 while leaving the
/// user's other key remaps intact.
public enum HyperRemap {
    public static let capsLock: UInt64 = 0x7_0000_0039
    public static let f18: UInt64 = 0x7_0000_006D
    public static let hyper = KeyMapping(src: capsLock, dst: f18)

    /// Parses `hidutil property --get UserKeyMapping`, which prints an old-style plist
    /// such as `( { HIDKeyboardModifierMappingDst = 30064771181; HIDKeyboardModifierMappingSrc = 30064771129; } )`
    /// or `(null)`.
    public static func parse(_ output: String) -> [KeyMapping] {
        guard let block = try? NSRegularExpression(pattern: "\\{([^}]*)\\}") else { return [] }
        let range = NSRange(output.startIndex..., in: output)
        return block.matches(in: output, range: range).compactMap { match in
            guard let body = Range(match.range(at: 1), in: output).map({ String(output[$0]) }),
                  let src = number(named: "HIDKeyboardModifierMappingSrc", in: body),
                  let dst = number(named: "HIDKeyboardModifierMappingDst", in: body) else { return nil }
            return KeyMapping(src: src, dst: dst)
        }
    }

    /// The value for `hidutil property --set`.
    public static func json(_ mappings: [KeyMapping]) -> String {
        let entries = mappings.map {
            "{\"HIDKeyboardModifierMappingSrc\":\($0.src),\"HIDKeyboardModifierMappingDst\":\($0.dst)}"
        }
        return "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
    }

    /// Replaces any existing Caps Lock remap with Caps Lock → F18. Returns the remap it
    /// displaced so `disabling` can put it back.
    public static func enabling(_ current: [KeyMapping]) -> (mappings: [KeyMapping], displaced: KeyMapping?) {
        let displaced = current.first { $0.src == capsLock && $0 != hyper }
        return (current.filter { $0.src != capsLock } + [hyper], displaced)
    }

    public static func disabling(_ current: [KeyMapping], restoring displaced: KeyMapping?) -> [KeyMapping] {
        current.filter { $0 != hyper } + (displaced.map { [$0] } ?? [])
    }

    private static func number(named key: String, in text: String) -> UInt64? {
        guard let regex = try? NSRegularExpression(pattern: key + "\\s*=\\s*(0x[0-9A-Fa-f]+|\\d+)"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let value = text[range]
        return value.hasPrefix("0x") ? UInt64(value.dropFirst(2), radix: 16) : UInt64(value)
    }
}
