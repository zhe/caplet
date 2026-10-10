import Foundation
import XCTest
@testable import TilerCore

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
