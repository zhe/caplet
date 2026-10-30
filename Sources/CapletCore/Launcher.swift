import Foundation

/// A ⇪ key that opens an app, such as ⇪T for Terminal.
public struct Launcher: Equatable, Sendable {
    /// The key's name as shown in the menu, such as "T".
    public var key: String
    public var keyCode: Int
    public var bundleID: String

    public init(key: String, keyCode: Int, bundleID: String) {
        self.key = key
        self.keyCode = keyCode
        self.bundleID = bundleID
    }
}

public enum LauncherProblem: Equatable, Sendable, CustomStringConvertible {
    case unknownKey(String)
    case taken(key: String, by: TileAction)
    case duplicateKey(String)
    case invalidBundleID(key: String)

    public var description: String {
        switch self {
        case .unknownKey(let key): return "“\(key)” isn't a key app shortcuts can use"
        case .taken(let key, let action): return "⇪\(key) is already \(action.title)"
        case .duplicateKey(let key): return "⇪\(key) is set more than once"
        case .invalidBundleID(let key): return "⇪\(key) needs an app's bundle ID"
        }
    }
}

public enum Launchers {
    /// The UserDefaults key holding a dictionary of key name → bundle ID, e.g. `{ T = "com.apple.Terminal"; }`.
    public static let defaultsKey = "launchers"

    /// Letters and digits by their US-layout names. Like the window keys, they are matched by
    /// physical position, so on other layouts a name means the key in the same place.
    public static let keyCodes: [String: Int] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06, "X": 0x07,
        "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10,
        "T": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
        "7": 0x1A, "8": 0x1C, "0": 0x1D, "O": 0x1F, "U": 0x20, "I": 0x22, "P": 0x23, "L": 0x25,
        "J": 0x26, "K": 0x28, "N": 0x2D, "M": 0x2E,
    ]

    /// Reads the stored dictionary. Key names are case-insensitive; entries that can't be used
    /// are left out and reported, so one typo doesn't turn off the others.
    public static func parse(_ config: [String: Any]) -> (launchers: [Launcher], problems: [LauncherProblem]) {
        var launchers: [Launcher] = []
        var problems: [LauncherProblem] = []
        for (name, value) in config.sorted(by: { $0.key < $1.key }) {
            let key = name.trimmingCharacters(in: .whitespaces).uppercased()
            guard let keyCode = keyCodes[key] else {
                problems.append(.unknownKey(name))
                continue
            }
            if let action = HyperBindings.actions[keyCode] {
                problems.append(.taken(key: key, by: action))
                continue
            }
            guard let bundleID = (value as? String)?.trimmingCharacters(in: .whitespaces), !bundleID.isEmpty else {
                problems.append(.invalidBundleID(key: key))
                continue
            }
            if launchers.contains(where: { $0.keyCode == keyCode }) {
                if !problems.contains(.duplicateKey(key)) { problems.append(.duplicateKey(key)) }
                continue
            }
            launchers.append(Launcher(key: key, keyCode: keyCode, bundleID: bundleID))
        }
        return (launchers.sorted { $0.key < $1.key }, problems)
    }
}
