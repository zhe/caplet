import Foundation

public enum HyperCommand: Hashable, Sendable {
    case tile(TileAction)
    case arrange(ArrangeAction)
    /// Opens the app with this bundle ID, or hides it when it's already in front.
    case launch(String)

    /// How the command is saved: "tile:leftHalf", "arrange:leftAndRight" or "app:com.apple.Safari".
    public var storedValue: String {
        switch self {
        case .tile(let action): return "tile:" + action.rawValue
        case .arrange(let action): return "arrange:" + action.rawValue
        case .launch(let bundleID): return "app:" + bundleID
        }
    }

    public init?(storedValue: String) {
        let parts = storedValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "tile": guard let action = TileAction(rawValue: parts[1]) else { return nil }; self = .tile(action)
        case "arrange": guard let action = ArrangeAction(rawValue: parts[1]) else { return nil }; self = .arrange(action)
        case "app": guard !parts[1].isEmpty else { return nil }; self = .launch(parts[1])
        default: return nil
        }
    }
}

/// ⇪ held alone, or together with ⌥. Each has its own bindings.
public enum HyperLayer: String, CaseIterable, Sendable {
    case caps
    case option

    public var symbol: String { self == .caps ? "⇪" : "⌥⇪" }
}

/// What each key does while ⇪ is held, per layer, keyed by macOS virtual key code. Key codes
/// follow physical position, so W A S D stay under the left hand on any keyboard layout.
/// A key may be bound in one layer and not the other, and several keys may run the same command.
public struct Keymap: Equatable, Sendable {
    /// The UserDefaults key holding `plist`.
    public static let defaultsKey = "keymap"
    /// F18 (kVK_F18). Caps Lock is remapped to it because Caps Lock itself only reports toggles.
    public static let triggerKeyCode = 0x4F

    public var layers: [HyperLayer: [Int: HyperCommand]]

    public init(_ layers: [HyperLayer: [Int: HyperCommand]] = [:]) {
        self.layers = layers
    }

    public static let defaults: Keymap = {
        let tiles: [Int: TileAction] = [
            0x0D: .topHalf, 0x00: .leftHalf, 0x01: .bottomHalf, 0x02: .rightHalf,         // W A S D
            0x0C: .topLeft, 0x0E: .topRight, 0x06: .bottomLeft, 0x07: .bottomRight,       // Q E Z X
            0x03: .maximize, 0x08: .center, 0x31: .nextDisplay,                           // F C Space
        ]
        let arranges: [Int: ArrangeAction] = [
            0x00: .leftAndRight, 0x02: .rightAndLeft, 0x0D: .topAndBottom, 0x01: .bottomAndTop,
            0x0C: .quartersFromTopLeft, 0x0E: .quartersFromTopRight,
            0x06: .quartersFromBottomLeft, 0x07: .quartersFromBottomRight,
        ]
        var option = tiles.filter { arranges[$0.key] == nil }.mapValues(HyperCommand.tile)
        option.merge(arranges.mapValues(HyperCommand.arrange)) { $1 }
        return Keymap([.caps: tiles.mapValues(HyperCommand.tile), .option: option])
    }()

    public subscript(layer: HyperLayer, keyCode: Int) -> HyperCommand? {
        get { layers[layer]?[keyCode] }
        set { layers[layer, default: [:]][keyCode] = newValue }
    }

    public func command(forKeyCode keyCode: Int, option: Bool) -> HyperCommand? {
        self[option ? .option : .caps, keyCode]
    }

    /// The shortcut shown for `command`, such as "⇪A" or "⌥⇪A": the first key in keyboard
    /// order that runs it, looking in the ⇪ layer before the ⌥⇪ one.
    public func label(for command: HyperCommand) -> String? {
        for layer in HyperLayer.allCases {
            let keys = (layers[layer] ?? [:]).filter { $0.value == command }.keys
            if let key = keys.min(by: Keyboard.precedes), let name = Keyboard.names[key] {
                return layer.symbol + name
            }
        }
        return nil
    }

    /// The value saved in UserDefaults: `{ caps = { 0 = "tile:leftHalf"; … }; option = { … }; }`.
    public var plist: [String: [String: String]] {
        var plist: [String: [String: String]] = [:]
        for layer in HyperLayer.allCases {
            plist[layer.rawValue] = Dictionary(uniqueKeysWithValues: (layers[layer] ?? [:]).map {
                (String($0.key), $0.value.storedValue)
            })
        }
        return plist
    }

    /// Reads `plist`. Nil when nothing usable is saved; entries that can't be read are skipped.
    public init?(plist: Any?) {
        guard let plist = plist as? [String: Any] else { return nil }
        self.init()
        for layer in HyperLayer.allCases {
            for (key, value) in plist[layer.rawValue] as? [String: Any] ?? [:] {
                guard let keyCode = Int(key), Keyboard.names[keyCode] != nil,
                      let command = (value as? String).flatMap(HyperCommand.init(storedValue:)) else { continue }
                self[layer, keyCode] = command
            }
        }
    }

    /// The UserDefaults key of the app shortcuts before `keymap`: key name → bundle ID.
    public static let launchersKey = "launchers"

    /// The defaults plus the app shortcuts of the old `launchers` setting. Those worked with
    /// or without ⌥, so they go into both layers. Entries that weren't usable are dropped.
    public static func migrating(launchers: Any?) -> Keymap {
        var keymap = defaults
        let codes = Dictionary(Keyboard.names.map { ($0.value, $0.key) }) { first, _ in first }
        for (name, value) in launchers as? [String: Any] ?? [:] {
            let name = name.trimmingCharacters(in: .whitespaces).uppercased()
            guard let keyCode = codes[name], keymap[.caps, keyCode] == nil,
                  let bundleID = (value as? String)?.trimmingCharacters(in: .whitespaces),
                  !bundleID.isEmpty else { continue }
            for layer in HyperLayer.allCases where keymap[layer, keyCode] == nil {
                keymap[layer, keyCode] = .launch(bundleID)
            }
        }
        return keymap
    }
}
