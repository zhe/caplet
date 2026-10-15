import Foundation
import XCTest
@testable import CapletCore

final class ArrangeTests: XCTestCase {
    private let laptop = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let external = CGRect(x: 1440, y: 0, width: 1920, height: 1055)

    func testPairsPutTheFocusedWindowFirst() {
        XCTAssertEqual(ArrangeAction.leftAndRight.slots, [.leftHalf, .rightHalf])
        XCTAssertEqual(ArrangeAction.rightAndLeft.slots, [.rightHalf, .leftHalf])
        XCTAssertEqual(ArrangeAction.topAndBottom.slots, [.topHalf, .bottomHalf])
        XCTAssertEqual(ArrangeAction.bottomAndTop.slots, [.bottomHalf, .topHalf])
    }

    func testQuartersStartAtTheChosenCornerThenReadingOrder() {
        XCTAssertEqual(ArrangeAction.quartersFromTopLeft.slots, [.topLeft, .topRight, .bottomLeft, .bottomRight])
        XCTAssertEqual(ArrangeAction.quartersFromBottomRight.slots, [.bottomRight, .topLeft, .topRight, .bottomLeft])
        XCTAssertEqual(ArrangeAction.quartersFromTopRight.slots, [.topRight, .topLeft, .bottomLeft, .bottomRight])
    }

    func testFramesTileWithoutGaps() {
        let frames = Arrange.frames(for: .leftAndRight, windowCount: 2, in: laptop)
        XCTAssertEqual(frames, [CGRect(x: 0, y: 25, width: 720, height: 875),
                                CGRect(x: 720, y: 25, width: 720, height: 875)])
    }

    func testFewerWindowsThanSlotsLeavesTheRestEmpty() {
        XCTAssertEqual(Arrange.frames(for: .quartersFromTopLeft, windowCount: 3, in: laptop).count, 3)
        XCTAssertEqual(Arrange.frames(for: .leftAndRight, windowCount: 1, in: laptop),
                       [CGRect(x: 0, y: 25, width: 720, height: 875)])
        XCTAssertEqual(Arrange.frames(for: .leftAndRight, windowCount: 5, in: laptop).count, 2)
        XCTAssertEqual(Arrange.frames(for: .leftAndRight, windowCount: 0, in: laptop), [])
    }

    func testFollowersKeepStackingOrderAndSkipOddWindows() {
        let focused = WindowSnapshot(id: 1, pid: 100, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let windows = [
            focused,
            WindowSnapshot(id: 2, pid: 200, frame: CGRect(x: 50, y: 50, width: 600, height: 400)),
            WindowSnapshot(id: 3, pid: 300, frame: CGRect(x: 0, y: 0, width: 1440, height: 25), layer: 24),
            WindowSnapshot(id: 4, pid: 400, frame: CGRect(x: 10, y: 40, width: 60, height: 40)),
            WindowSnapshot(id: 5, pid: 500, frame: CGRect(x: 1600, y: 100, width: 900, height: 700)),
            WindowSnapshot(id: 6, pid: 600, frame: CGRect(x: 300, y: 200, width: 500, height: 500), alpha: 0),
            WindowSnapshot(id: 7, pid: 999, frame: CGRect(x: 300, y: 200, width: 500, height: 500)),
            WindowSnapshot(id: 8, pid: 100, frame: CGRect(x: 200, y: 300, width: 700, height: 500)),
            WindowSnapshot(id: 9, pid: 200, frame: CGRect(x: 400, y: 100, width: 700, height: 500)),
        ]
        let followers = Arrange.followers(of: focused, frontToBack: windows,
                                          screens: [laptop, external], excludingPID: 999)
        XCTAssertEqual(followers.map(\.id), [2, 8, 9])
    }

    func testFollowersOnTheExternalDisplay() {
        let focused = WindowSnapshot(id: 1, pid: 100, frame: CGRect(x: 1600, y: 100, width: 900, height: 700))
        let windows = [
            WindowSnapshot(id: 2, pid: 200, frame: CGRect(x: 100, y: 100, width: 800, height: 600)),
            WindowSnapshot(id: 3, pid: 300, frame: CGRect(x: 2000, y: 300, width: 900, height: 600)),
        ]
        XCTAssertEqual(Arrange.followers(of: focused, frontToBack: windows, screens: [laptop, external],
                                         excludingPID: 999).map(\.id), [3])
    }

    func testOptionSwitchesToArrange() {
        XCTAssertEqual(HyperBindings.command(forKeyCode: 0x00, option: false), .tile(.leftHalf))
        XCTAssertEqual(HyperBindings.command(forKeyCode: 0x00, option: true), .arrange(.leftAndRight))
        XCTAssertEqual(HyperBindings.command(forKeyCode: 0x07, option: true), .arrange(.quartersFromBottomRight))
        XCTAssertEqual(HyperBindings.command(forKeyCode: 0x03, option: true), .tile(.maximize))
        XCTAssertNil(HyperBindings.command(forKeyCode: 0x05, option: true))
    }

    func testEveryArrangeActionHasAKey() {
        for action in ArrangeAction.allCases {
            XCTAssertNotNil(HyperBindings.keyLabel(for: action), "\(action) has no key")
        }
        XCTAssertEqual(HyperBindings.keyLabel(for: .leftAndRight), "A")
        XCTAssertEqual(HyperBindings.keyLabel(for: .quartersFromTopLeft), "Q")
    }
}
