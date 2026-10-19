import Foundation
import XCTest
@testable import CapletCore

final class HyperKeyTests: XCTestCase {
    func testWASDMapToDirections() {
        XCTAssertEqual(HyperBindings.action(forKeyCode: 0x0D), .topHalf)
        XCTAssertEqual(HyperBindings.action(forKeyCode: 0x00), .leftHalf)
        XCTAssertEqual(HyperBindings.action(forKeyCode: 0x01), .bottomHalf)
        XCTAssertEqual(HyperBindings.action(forKeyCode: 0x02), .rightHalf)
        XCTAssertNil(HyperBindings.action(forKeyCode: 0x05)) // G
    }

    func testCornersKeepCenterAndFill() {
        XCTAssertEqual(HyperBindings.action(forKeyCode: 0x0C), .topLeft)     // Q
        XCTAssertEqual(HyperBindings.action(forKeyCode: 0x0E), .topRight)    // E
        XCTAssertEqual(HyperBindings.action(forKeyCode: 0x06), .bottomLeft)  // Z
        XCTAssertEqual(HyperBindings.action(forKeyCode: 0x07), .bottomRight) // X
        XCTAssertEqual(HyperBindings.action(forKeyCode: 0x08), .center)      // C
        XCTAssertEqual(HyperBindings.action(forKeyCode: 0x03), .maximize)    // F
        XCTAssertEqual(HyperBindings.action(forKeyCode: 0x31), .nextDisplay) // Space
    }

    func testEachKeyHasOneAction() {
        XCTAssertEqual(Set(HyperBindings.actions.values).count, HyperBindings.actions.count)
    }

    func testEveryActionHasAHyperKey() {
        for action in TileAction.allCases {
            XCTAssertNotNil(HyperBindings.keyLabels[action], "\(action) has no hyper key")
            XCTAssertTrue(HyperBindings.actions.values.contains(action))
        }
    }

    func testUsageConstantsMatchHidutilValues() {
        XCTAssertEqual(HyperRemap.capsLock, 30_064_771_129)
        XCTAssertEqual(HyperRemap.f18, 30_064_771_181)
    }

    func testParsesHidutilOutput() {
        let output = """
        (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            },
                {
                HIDKeyboardModifierMappingDst = 0x7000000E0;
                HIDKeyboardModifierMappingSrc = 0x7000000E3;
            }
        )
        """
        XCTAssertEqual(HyperRemap.parse(output), [
            HyperRemap.hyper,
            KeyMapping(src: 0x7_0000_00E3, dst: 0x7_0000_00E0),
        ])
    }

    // Recent macOS prints one row per HID service. The keyboard here has Raycast's Caps Lock → F20.
    private let perServiceOutput = """
    RegistryID  Key                   Value
    100000aa8   UserKeyMapping   (
            {
            HIDKeyboardModifierMappingDst = 30064771181;
            HIDKeyboardModifierMappingSrc = 30064771129;
        }
    )
    1000006a8   UserKeyMapping   (null)
    100000aab   UserKeyMapping   (
            {
            HIDKeyboardModifierMappingDst = 30064771183;
            HIDKeyboardModifierMappingSrc = 30064771129;
        },
            {
            HIDKeyboardModifierMappingDst = 30064771181;
            HIDKeyboardModifierMappingSrc = 30064771129;
        }
    )
    """

    func testParsesEachServiceAndListsEachRemapOnce() {
        let f20 = KeyMapping(src: HyperRemap.capsLock, dst: 0x7_0000_006F)
        XCTAssertEqual(HyperRemap.parseServices(perServiceOutput), [[HyperRemap.hyper], [], [f20, HyperRemap.hyper]])
        XCTAssertEqual(HyperRemap.parse(perServiceOutput), [HyperRemap.hyper, f20])
        XCTAssertEqual(HyperRemap.parseServices("(null)\n"), [[]])
    }

    func testCheckFindsMissingAndTakenCapsLock() {
        let f20: UInt64 = 0x7_0000_006F
        let swapCmdOpt = KeyMapping(src: 0x7_0000_00E3, dst: 0x7_0000_00E2)
        XCTAssertEqual(HyperRemap.check(keyboards: [[swapCmdOpt, HyperRemap.hyper], [HyperRemap.hyper]]), .intact)
        XCTAssertEqual(HyperRemap.check(keyboards: [[HyperRemap.hyper], [swapCmdOpt]]), .missing)
        // Another app's remap wins over a missing one: re-adding F18 there would overwrite it.
        XCTAssertEqual(HyperRemap.check(keyboards: [[], [KeyMapping(src: HyperRemap.capsLock, dst: f20)]]),
                       .taken(by: f20))
        XCTAssertEqual(HyperRemap.check(keyboards: []), .intact)
    }

    func testKeyNames() {
        XCTAssertEqual(HyperRemap.keyName(0x7_0000_006F), "F20")
        XCTAssertEqual(HyperRemap.keyName(HyperRemap.f18), "F18")
        XCTAssertEqual(HyperRemap.keyName(0x7_0000_003A), "F1")
        XCTAssertEqual(HyperRemap.keyName(0x7_0000_0029), "Escape")
        XCTAssertNil(HyperRemap.keyName(0x7_0000_0004)) // A
        XCTAssertNil(HyperRemap.keyName(0xFF_0000_0003))
    }

    func testParsesNull() {
        XCTAssertEqual(HyperRemap.parse("(null)\n"), [])
    }

    func testJSONForHidutilSet() {
        XCTAssertEqual(HyperRemap.json([HyperRemap.hyper]),
                       "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":30064771129,\"HIDKeyboardModifierMappingDst\":30064771181}]}")
        XCTAssertEqual(HyperRemap.json([]), "{\"UserKeyMapping\":[]}")
    }

    func testEnableKeepsOtherRemapsAndDisableRestoresCapsLock() {
        let swapCmdOpt = KeyMapping(src: 0x7_0000_00E3, dst: 0x7_0000_00E2)
        let capsToEscape = KeyMapping(src: HyperRemap.capsLock, dst: 0x7_0000_0029)

        let enabled = HyperRemap.enabling([swapCmdOpt, capsToEscape])
        XCTAssertEqual(enabled.mappings, [swapCmdOpt, HyperRemap.hyper])
        XCTAssertEqual(enabled.displaced, capsToEscape)

        XCTAssertEqual(HyperRemap.disabling(enabled.mappings, restoring: enabled.displaced),
                       [swapCmdOpt, capsToEscape])
    }

    func testEnableIsIdempotentAfterACrash() {
        let enabled = HyperRemap.enabling([HyperRemap.hyper])
        XCTAssertEqual(enabled.mappings, [HyperRemap.hyper])
        XCTAssertNil(enabled.displaced)
        XCTAssertEqual(HyperRemap.disabling(enabled.mappings, restoring: nil), [])
    }
}
