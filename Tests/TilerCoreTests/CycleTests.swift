import Foundation
import XCTest
@testable import TilerCore

final class CycleTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 25, width: 1441, height: 875)

    private func frame(_ action: TileAction, step: Int) -> CGRect {
        Layout.frame(for: action, in: screen, fraction: Cycle.fractions[step])!
    }

    func testFractionsTileWithoutGaps() {
        let leftThird = Layout.frame(for: .leftHalf, in: screen, fraction: 1.0 / 3)!
        let rightTwoThirds = Layout.frame(for: .rightHalf, in: screen, fraction: 2.0 / 3)!
        XCTAssertEqual(leftThird, CGRect(x: 0, y: 25, width: 480, height: 875))
        XCTAssertEqual(rightTwoThirds, CGRect(x: 480, y: 25, width: 961, height: 875))

        let leftTwoThirds = Layout.frame(for: .leftHalf, in: screen, fraction: 2.0 / 3)!
        let rightThird = Layout.frame(for: .rightHalf, in: screen, fraction: 1.0 / 3)!
        XCTAssertEqual(leftTwoThirds.maxX, rightThird.minX)
        XCTAssertEqual(rightThird.maxX, screen.maxX)
    }

    func testTopAndBottomTileWithoutGaps() {
        let top = Layout.frame(for: .topHalf, in: screen)!
        let bottom = Layout.frame(for: .bottomHalf, in: screen)!
        XCTAssertEqual(top, CGRect(x: 0, y: 25, width: 1441, height: 437))
        XCTAssertEqual(bottom, CGRect(x: 0, y: 462, width: 1441, height: 438))

        let topThird = Layout.frame(for: .topHalf, in: screen, fraction: 1.0 / 3)!
        let bottomTwoThirds = Layout.frame(for: .bottomHalf, in: screen, fraction: 2.0 / 3)!
        XCTAssertEqual(topThird.maxY, bottomTwoThirds.minY)
        XCTAssertEqual(bottomTwoThirds.maxY, screen.maxY)
    }

    func testTopCycles() {
        XCTAssertEqual(Cycle.nextStep(for: .topHalf, window: frame(.topHalf, step: 0), screen: screen, last: nil), 1)
        XCTAssertEqual(Cycle.nextStep(for: .bottomHalf, window: frame(.bottomHalf, step: 2), screen: screen, last: nil), 0)
    }

    func testUntiledWindowStartsAtHalf() {
        let window = CGRect(x: 200, y: 200, width: 600, height: 400)
        XCTAssertEqual(Cycle.nextStep(for: .leftHalf, window: window, screen: screen, last: nil), 0)
    }

    func testRepeatedPressesCycleAndWrap() {
        var last: CycleRecord?
        var window = CGRect(x: 200, y: 200, width: 600, height: 400)
        var steps: [Int] = []
        for _ in 0..<4 {
            let step = Cycle.nextStep(for: .rightHalf, window: window, screen: screen, last: last)
            window = frame(.rightHalf, step: step)
            last = CycleRecord(action: .rightHalf, step: step, screen: screen, achieved: window)
            steps.append(step)
        }
        XCTAssertEqual(steps, [0, 1, 2, 0])
    }

    func testAdvancesWhenAppRoundedTheFrame() {
        // Terminal-style rounding: the app accepted a slightly different size than requested.
        let achieved = CGRect(x: 0, y: 25, width: 714, height: 868)
        let last = CycleRecord(action: .leftHalf, step: 0, screen: screen, achieved: achieved)
        XCTAssertEqual(Cycle.nextStep(for: .leftHalf, window: achieved, screen: screen, last: last), 1)
    }

    func testRecognisesCycleFrameWithoutHistory() {
        XCTAssertEqual(Cycle.nextStep(for: .leftHalf, window: frame(.leftHalf, step: 1),
                                      screen: screen, last: nil), 2)
    }

    func testOtherDirectionStartsOver() {
        let window = frame(.leftHalf, step: 0)
        let last = CycleRecord(action: .leftHalf, step: 0, screen: screen, achieved: window)
        XCTAssertEqual(Cycle.nextStep(for: .rightHalf, window: window, screen: screen, last: last), 0)
    }

    func testMovedWindowStartsOver() {
        let last = CycleRecord(action: .leftHalf, step: 1, screen: screen, achieved: frame(.leftHalf, step: 1))
        let moved = CGRect(x: 300, y: 100, width: 700, height: 500)
        XCTAssertEqual(Cycle.nextStep(for: .leftHalf, window: moved, screen: screen, last: last), 0)
    }

    func testOtherScreenStartsOver() {
        let other = CGRect(x: 1441, y: 0, width: 1920, height: 1055)
        let window = CGRect(x: 1500, y: 40, width: 900, height: 700)
        let last = CycleRecord(action: .leftHalf, step: 1, screen: screen, achieved: window)
        XCTAssertEqual(Cycle.nextStep(for: .leftHalf, window: window, screen: other, last: last), 0)
    }

    func testOnlySidesCycle() {
        XCTAssertEqual(Cycle.nextStep(for: .maximize, window: screen, screen: screen, last: nil), 0)
        XCTAssertFalse(Cycle.supports(.nextDisplay))
    }
}
