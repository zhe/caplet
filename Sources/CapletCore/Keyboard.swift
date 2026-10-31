import Foundation

/// The physical arrangement of a Mac keyboard. ISO keyboards (British, German, …) have an
/// L-shaped Return, a key left of Z, and § where ANSI has `.
public enum KeyboardShape: Sendable {
    case ansi
    case iso
}

/// One key of the keyboard drawn in Settings, measured in key widths ("units") from the
/// top-left corner.
public struct KeyCap: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A key ⇪ shortcuts can use, with its macOS virtual key code.
        case bindable(Int)
        case capsLock
        /// Either ⌥ key, with its virtual key code. Clicking it shows the ⌥⇪ layer.
        case option(Int)
        /// ISO Return: `x`…`x + width` on its top row, and a quarter unit narrower on the row below.
        case isoReturn
        /// Tab, Shift, Command and the like, drawn for orientation only, with their virtual key code.
        case fixed(Legend, Int)
    }

    public enum Legend: Sendable {
        case delete, tab, returnKey, shift, function, control, command
    }

    /// The key's virtual key code, if it has one Settings can see pressed. Caps Lock has none:
    /// Caplet turns it into F18 and swallows it.
    public var keyCode: Int? {
        switch kind {
        case .bindable(let code), .option(let code), .fixed(_, let code): return code
        case .isoReturn: return 0x24
        case .capsLock: return nil
        }
    }

    public var kind: Kind
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
}

/// A 65%-style Mac keyboard: number row, three letter rows, and the bottom row with arrows.
/// Virtual key codes follow physical position, so the same drawing serves every layout.
public enum Keyboard {
    public static let width = 15.0
    public static let height = 5.0

    /// Short names of the bindable keys, after their legend on a US keyboard (§ on ISO).
    public static let names: [Int: String] = [
        0x0A: "§", 0x32: "`", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6",
        0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0", 0x1B: "-", 0x18: "=",
        0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x11: "T", 0x10: "Y", 0x20: "U", 0x22: "I",
        0x1F: "O", 0x23: "P", 0x21: "[", 0x1E: "]", 0x2A: "\\",
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x05: "G", 0x04: "H", 0x26: "J", 0x28: "K",
        0x25: "L", 0x29: ";", 0x27: "'",
        0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x2D: "N", 0x2E: "M", 0x2B: ",",
        0x2F: ".", 0x2C: "/",
        0x31: "␣", 0x7B: "←", 0x7C: "→", 0x7E: "↑", 0x7D: "↓",
    ]

    public static func keys(_ shape: KeyboardShape) -> [KeyCap] {
        let iso = shape == .iso
        var keys = row(0, [key(iso ? 0x0A : 0x32)] + codes(0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C,
                                                         0x19, 0x1D, 0x1B, 0x18) + [(.fixed(.delete, 0x33), 2)])
        keys += row(1, [(.fixed(.tab, 0x30), 1.5)] + codes(0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x10, 0x20, 0x22, 0x1F, 0x23, 0x21, 0x1E)
                    + [iso ? (.isoReturn, 1.5) : (.bindable(0x2A), 1.5)])
        keys += row(2, [(.capsLock, 1.75)] + codes(0x00, 0x01, 0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25, 0x29, 0x27)
                    + [iso ? key(0x2A) : (.fixed(.returnKey, 0x24), 2.25)])
        let shift: (KeyCap.Kind, Double) = (.fixed(.shift, 0x38), iso ? 1.25 : 2.25)
        keys += row(3, (iso ? [shift, key(0x32)] : [shift])
                    + codes(0x06, 0x07, 0x08, 0x09, 0x0B, 0x2D, 0x2E, 0x2B, 0x2F, 0x2C) + [(.fixed(.shift, 0x3C), 2.75)])
        // A Mac's bottom row: fn ⌃ ⌥ ⌘ space ⌘ ⌥, then the arrows.
        keys += row(4, [(.fixed(.function, 0x3F), 1), (.fixed(.control, 0x3B), 1), (.option(0x3A), 1),
                        (.fixed(.command, 0x37), 1.25), (.bindable(0x31), 5.5), (.fixed(.command, 0x36), 1.25),
                        (.option(0x3D), 1)])
        if let index = keys.firstIndex(where: { $0.kind == .isoReturn }) { keys[index].height = 2 }
        // Apple's arrows: ← and → half height at the bottom, ↑ above ↓.
        keys += [
            KeyCap(kind: .bindable(0x7B), x: 12, y: 4.5, width: 1, height: 0.5),
            KeyCap(kind: .bindable(0x7E), x: 13, y: 4, width: 1, height: 0.5),
            KeyCap(kind: .bindable(0x7D), x: 13, y: 4.5, width: 1, height: 0.5),
            KeyCap(kind: .bindable(0x7C), x: 14, y: 4.5, width: 1, height: 0.5),
        ]
        return keys
    }

    /// Whether key `a` comes before key `b` reading the keyboard row by row, left to right.
    public static func precedes(_ a: Int, _ b: Int) -> Bool {
        (order[a] ?? .max, a) < (order[b] ?? .max, b)
    }

    private static let order: [Int: Int] = {
        let codes = (keys(.iso) + keys(.ansi)).compactMap { key -> (Int, Double)? in
            guard case .bindable(let code) = key.kind else { return nil }
            return (code, key.y * 100 + key.x)
        }
        let sorted = codes.sorted { $0.1 < $1.1 }.map(\.0)
        var order: [Int: Int] = [:]
        for (index, code) in sorted.enumerated() where order[code] == nil { order[code] = index }
        return order
    }()

    private static func key(_ code: Int) -> (KeyCap.Kind, Double) { (.bindable(code), 1) }

    private static func codes(_ codes: Int...) -> [(KeyCap.Kind, Double)] { codes.map(key) }

    private static func row(_ y: Double, _ items: [(KeyCap.Kind, Double)]) -> [KeyCap] {
        var x = 0.0
        return items.map { kind, width in
            defer { x += width }
            return KeyCap(kind: kind, x: x, y: y, width: width, height: 1)
        }
    }
}
