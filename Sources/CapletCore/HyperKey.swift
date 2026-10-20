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
        0x0C: .topLeft,     // Q
        0x0E: .topRight,    // E
        0x06: .bottomLeft,  // Z
        0x07: .bottomRight, // X
        0x03: .maximize,    // F
        0x08: .center,      // C
        0x31: .nextDisplay, // Space
    ]

    public static let keyLabels: [TileAction: String] = [
        .topHalf: "W", .leftHalf: "A", .bottomHalf: "S", .rightHalf: "D",
        .topLeft: "Q", .topRight: "E", .bottomLeft: "Z", .bottomRight: "X",
        .maximize: "F", .center: "C", .nextDisplay: "␣",
    ]

    /// With ⌥ also held, the same keys arrange the windows behind the focused one too.
    public static let arrangeActions: [Int: ArrangeAction] = [
        0x00: .leftAndRight,            // A
        0x02: .rightAndLeft,            // D
        0x0D: .topAndBottom,            // W
        0x01: .bottomAndTop,            // S
        0x0C: .quartersFromTopLeft,     // Q
        0x0E: .quartersFromTopRight,    // E
        0x06: .quartersFromBottomLeft,  // Z
        0x07: .quartersFromBottomRight, // X
    ]

    public static func action(forKeyCode keyCode: Int) -> TileAction? {
        actions[keyCode]
    }

    /// ⌥ with a key that has no arrange binding (⌥⇪F) falls back to the plain action.
    public static func command(forKeyCode keyCode: Int, option: Bool) -> HyperCommand? {
        if option, let arrange = arrangeActions[keyCode] { return .arrange(arrange) }
        return actions[keyCode].map(HyperCommand.tile)
    }

    /// The key for an arrange action, e.g. "A" for Left & Right.
    public static func keyLabel(for arrange: ArrangeAction) -> String? {
        arrangeActions.first { $0.value == arrange }.flatMap { actions[$0.key] }.flatMap { keyLabels[$0] }
    }
}

public enum HyperCommand: Equatable, Sendable {
    case tile(TileAction)
    case arrange(ArrangeAction)
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

public enum RemapCheck: Equatable, Sendable {
    case intact
    /// A keyboard has no Caps Lock remap, e.g. one plugged in after Caplet set it.
    case missing
    /// A keyboard sends another key for Caps Lock: another app remapped it after Caplet.
    case taken(by: UInt64)
}

/// Builds `hidutil property` arguments that remap Caps Lock to F18 while leaving the
/// user's other key remaps intact.
public enum HyperRemap {
    public static let capsLock: UInt64 = 0x7_0000_0039
    public static let f18: UInt64 = 0x7_0000_006D
    public static let hyper = KeyMapping(src: capsLock, dst: f18)

    /// Parses `hidutil property --get UserKeyMapping`, which prints an old-style plist
    /// such as `( { HIDKeyboardModifierMappingDst = 30064771181; HIDKeyboardModifierMappingSrc = 30064771129; } )`
    /// or `(null)`, once per HID service on recent macOS. Each remap is listed once.
    public static func parse(_ output: String) -> [KeyMapping] {
        guard let block = try? NSRegularExpression(pattern: "\\{([^}]*)\\}") else { return [] }
        let range = NSRange(output.startIndex..., in: output)
        var mappings: [KeyMapping] = []
        for match in block.matches(in: output, range: range) {
            guard let body = Range(match.range(at: 1), in: output).map({ String(output[$0]) }),
                  let src = number(named: "HIDKeyboardModifierMappingSrc", in: body),
                  let dst = number(named: "HIDKeyboardModifierMappingDst", in: body) else { continue }
            let mapping = KeyMapping(src: src, dst: dst)
            if !mappings.contains(mapping) { mappings.append(mapping) }
        }
        return mappings
    }

    /// The remaps of each HID service. Recent macOS starts each service's row with its
    /// registry ID (`100000aab   UserKeyMapping   ( ... )`); older versions print one plist.
    public static func parseServices(_ output: String) -> [[KeyMapping]] {
        var rows: [String] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let fields = line.split(separator: " ", maxSplits: 2)
            if fields.count >= 2, fields[1] == "UserKeyMapping", UInt64(fields[0], radix: 16) != nil {
                rows.append(String(line))
            } else if !rows.isEmpty {
                rows[rows.count - 1] += "\n" + line
            }
        }
        return rows.isEmpty ? [parse(output)] : rows.map(parse)
    }

    /// Whether every keyboard still sends F18 for Caps Lock.
    public static func check(keyboards: [[KeyMapping]]) -> RemapCheck {
        let targets = keyboards.map { mappings in mappings.first { $0.src == capsLock }?.dst }
        if let other = targets.compactMap({ $0 }).first(where: { $0 != f18 }) { return .taken(by: other) }
        return targets.contains(nil) ? .missing : .intact
    }

    /// A readable name for a remap target, such as "F20", or nil for keys without a short name.
    public static func keyName(_ usage: UInt64) -> String? {
        guard usage >> 32 == 7 else { return nil }
        switch usage & 0xFFFF_FFFF {
        case let key where (0x3A...0x45).contains(key): return "F\(key - 0x3A + 1)"
        case let key where (0x68...0x73).contains(key): return "F\(key - 0x68 + 13)"
        case 0x29: return "Escape"
        case 0x39: return "Caps Lock"
        case 0xE0, 0xE4: return "Control"
        case 0xE1, 0xE5: return "Shift"
        case 0xE2, 0xE6: return "Option"
        case 0xE3, 0xE7: return "Command"
        default: return nil
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
