import XCTest
@testable import CapletCore

final class LauncherTests: XCTestCase {
    func testKeysMapToPhysicalPositions() {
        // Key codes follow the keyboard, not the alphabet: G comes before B, and 6 before 5.
        let (launchers, problems) = Launchers.parse([
            "b": "com.apple.Terminal", "G": "com.google.Chrome", "5": "a.five", "6": "a.six",
        ])
        XCTAssertEqual(problems, [])
        XCTAssertEqual(launchers, [
            Launcher(key: "5", keyCode: 0x17, bundleID: "a.five"),
            Launcher(key: "6", keyCode: 0x16, bundleID: "a.six"),
            Launcher(key: "B", keyCode: 0x0B, bundleID: "com.apple.Terminal"),
            Launcher(key: "G", keyCode: 0x05, bundleID: "com.google.Chrome"),
        ])
    }

    func testUnusableEntriesAreReportedAndTheRestKept() {
        let (launchers, problems) = Launchers.parse([
            "w": "com.apple.Terminal", // window shortcut
            "Tab": "com.apple.Notes",
            "R": "",
            "T": 42,
            "V": "com.apple.Safari",
        ])
        XCTAssertEqual(launchers, [Launcher(key: "V", keyCode: 0x09, bundleID: "com.apple.Safari")])
        XCTAssertEqual(Set(problems.map(\.description)), [
            "⇪W is already Top Half",
            "“Tab” isn't a key app shortcuts can use",
            "⇪R needs an app's bundle ID",
            "⇪T needs an app's bundle ID",
        ])
    }

    func testNoLauncherKeyShadowsAWindowShortcut() {
        let config = Dictionary(uniqueKeysWithValues: Launchers.keyCodes.keys.map { ($0, "app") })
        let launchers = Launchers.parse(config).launchers
        XCTAssertEqual(launchers.count, Launchers.keyCodes.count - 10) // Space has no name
        XCTAssertTrue(launchers.allSatisfy { HyperBindings.actions[$0.keyCode] == nil })
    }

    func testSameKeyInBothCasesIsReportedOnce() {
        let (launchers, problems) = Launchers.parse(["b": "one", "B": "two"])
        XCTAssertEqual(launchers.count, 1)
        XCTAssertEqual(problems, [.duplicateKey("B")])
    }

    func testLauncherKeysLaunchWithOrWithoutOption() {
        let launchers = [0x0B: "com.apple.Terminal", 0x00: "shadowed"]
        XCTAssertEqual(HyperBindings.command(forKeyCode: 0x0B, option: false, launchers: launchers),
                       .launch("com.apple.Terminal"))
        XCTAssertEqual(HyperBindings.command(forKeyCode: 0x0B, option: true, launchers: launchers),
                       .launch("com.apple.Terminal"))
        // Window shortcuts always win.
        XCTAssertEqual(HyperBindings.command(forKeyCode: 0x00, option: false, launchers: launchers),
                       .tile(.leftHalf))
        XCTAssertNil(HyperBindings.command(forKeyCode: 0x05, option: false, launchers: launchers))
    }
}
