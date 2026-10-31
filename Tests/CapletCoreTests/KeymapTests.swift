import XCTest
@testable import CapletCore

final class KeymapTests: XCTestCase {
    func testDefaultsKeepTheOriginalShortcuts() {
        let keymap = Keymap.defaults
        XCTAssertEqual(keymap.command(forKeyCode: 0x0D, option: false), .tile(.topHalf))       // W
        XCTAssertEqual(keymap.command(forKeyCode: 0x00, option: false), .tile(.leftHalf))      // A
        XCTAssertEqual(keymap.command(forKeyCode: 0x31, option: false), .tile(.nextDisplay))   // Space
        XCTAssertEqual(keymap.command(forKeyCode: 0x00, option: true), .arrange(.leftAndRight))
        XCTAssertEqual(keymap.command(forKeyCode: 0x07, option: true), .arrange(.quartersFromBottomRight))
        // ⌥ with F, C or Space does the same as without it.
        XCTAssertEqual(keymap.command(forKeyCode: 0x03, option: true), .tile(.maximize))
        XCTAssertNil(keymap.command(forKeyCode: 0x05, option: false)) // G
        for action in TileAction.allCases { XCTAssertNotNil(keymap.label(for: .tile(action)), "\(action)") }
        for action in ArrangeAction.allCases { XCTAssertNotNil(keymap.label(for: .arrange(action)), "\(action)") }
    }

    func testLayersAreIndependent() {
        var keymap = Keymap.defaults
        keymap[.caps, 0x00] = nil
        keymap[.option, 0x05] = .launch("com.apple.Safari")
        XCTAssertNil(keymap.command(forKeyCode: 0x00, option: false))
        XCTAssertEqual(keymap.command(forKeyCode: 0x00, option: true), .arrange(.leftAndRight))
        XCTAssertEqual(keymap.command(forKeyCode: 0x05, option: true), .launch("com.apple.Safari"))
        XCTAssertNil(keymap.command(forKeyCode: 0x05, option: false))
    }

    func testLabelIsTheFirstKeyInKeyboardOrderAndPrefersTheCapsLayer() {
        var keymap = Keymap()
        // Key codes don't follow the keyboard: G (0x05) comes before H (0x04), and 1 (0x12)
        // before Q (0x0C).
        keymap[.caps, 0x04] = .tile(.leftHalf)   // H
        keymap[.caps, 0x05] = .tile(.leftHalf)   // G
        XCTAssertEqual(keymap.label(for: .tile(.leftHalf)), "⇪G")
        keymap[.caps, 0x12] = .tile(.leftHalf)   // 1
        keymap[.caps, 0x0C] = .tile(.leftHalf)   // Q
        XCTAssertEqual(keymap.label(for: .tile(.leftHalf)), "⇪1")
        keymap[.option, 0x0C] = .launch("app")
        XCTAssertEqual(keymap.label(for: .launch("app")), "⌥⇪Q")
        keymap[.caps, 0x2C] = .launch("app")     // /
        XCTAssertEqual(keymap.label(for: .launch("app")), "⇪/")
        XCTAssertNil(keymap.label(for: .tile(.center)))
    }

    func testSavedPlistRoundTripsAndSkipsWhatItCantRead() {
        var keymap = Keymap.defaults
        keymap[.caps, 0x00] = nil
        keymap[.option, 0x11] = .launch("com.apple.Terminal")
        XCTAssertEqual(Keymap(plist: keymap.plist as Any), keymap)

        let read = Keymap(plist: [
            "caps": ["13": "tile:topHalf", "5": "app:com.apple.Notes", "6": "tile:sideways", "7": "app:",
                     "x": "tile:center", "79": "tile:center", "8": 42],
            "option": ["0": "arrange:leftAndRight"],
            "shift": ["1": "tile:center"],
        ] as [String: Any])
        XCTAssertEqual(read, Keymap([
            .caps: [0x0D: .tile(.topHalf), 0x05: .launch("com.apple.Notes")],
            .option: [0x00: .arrange(.leftAndRight)],
        ]))
        XCTAssertNil(Keymap(plist: "not a dictionary"))
        XCTAssertNil(Keymap(plist: nil))
    }

    func testOldAppShortcutsMoveIntoBothLayers() {
        let keymap = Keymap.migrating(launchers: [
            "b": "com.apple.Safari", "W": "com.apple.Terminal", "R": " ", "Tab": "com.apple.Notes", "T": 42,
        ] as [String: Any])
        var expected = Keymap.defaults
        expected[.caps, 0x0B] = .launch("com.apple.Safari")
        expected[.option, 0x0B] = .launch("com.apple.Safari")
        XCTAssertEqual(keymap, expected)
        XCTAssertEqual(Keymap.migrating(launchers: "junk"), .defaults)
    }

    func testKeyboardsAreFifteenUnitsWideWithEachKeyOnce() {
        for shape in [KeyboardShape.ansi, .iso] {
            let keys = Keyboard.keys(shape)
            for row in 0..<4 {
                let width = keys.filter { $0.y == Double(row) || ($0.kind == .isoReturn && row == 2) }
                    .map { $0.kind == .isoReturn && row == 2 ? $0.width - 0.25 : $0.width }.reduce(0, +)
                XCTAssertEqual(width, Keyboard.width, "\(shape) row \(row)")
            }
            XCTAssertTrue(keys.allSatisfy { $0.x + $0.width <= Keyboard.width && $0.y + $0.height <= Keyboard.height })
            let codes = keys.compactMap { key -> Int? in
                if case .bindable(let code) = key.kind { return code }
                return nil
            }
            XCTAssertEqual(Set(codes).count, codes.count, "\(shape)")
            XCTAssertTrue(codes.allSatisfy { Keyboard.names[$0] != nil })
        }
        // ISO has § top-left and ` left of Z; ANSI has ` top-left and \ above Return.
        XCTAssertEqual(Keyboard.keys(.iso).first?.kind, .bindable(0x0A))
        XCTAssertEqual(Keyboard.keys(.ansi).first?.kind, .bindable(0x32))
        XCTAssertFalse(Keyboard.keys(.ansi).contains { $0.kind == .bindable(0x0A) })
    }
}
