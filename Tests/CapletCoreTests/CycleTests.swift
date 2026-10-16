import Foundation
import XCTest
@testable import CapletCore

final class CycleTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 25, width: 1441, height: 875)

    /// The ½, ⅔ or ⅓ frame, by index into `Cycle.fractions`. Its step is `fraction + 1`.
    private func frame(_ action: TileAction, fraction: Int) -> CGRect {
        Layout.frame(for: action, in: screen, fraction: Cycle.fractions[fraction])!
    }

    /// Simulates presses, with the app accepting every requested frame.
    private func press(_ action: TileAction, _ times: Int, from start: CGRect) -> [CGRect] {
        var window = start
        var last: CycleRecord?
        var frames: [CGRect] = []
        for _ in 0..<times {
            let step = Cycle.nextStep(for: action, window: window, screen: screen, last: last)
            window = Cycle.target(for: action, step: step, window: window, screen: screen)!
            last = CycleRecord(action: action, step: step, screen: screen, achieved: window)
            frames.append(window)
        }
        return frames
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

    func testCornersTileTheScreen() {
        let tl = Layout.frame(for: .topLeft, in: screen)!
        let tr = Layout.frame(for: .topRight, in: screen)!
        let bl = Layout.frame(for: .bottomLeft, in: screen)!
        let br = Layout.frame(for: .bottomRight, in: screen)!
        XCTAssertEqual(tl, CGRect(x: 0, y: 25, width: 720, height: 437))
        XCTAssertEqual(tr, CGRect(x: 720, y: 25, width: 721, height: 437))
        XCTAssertEqual(bl, CGRect(x: 0, y: 462, width: 720, height: 438))
        XCTAssertEqual(br, CGRect(x: 720, y: 462, width: 721, height: 438))
    }

    func testCornerCyclesWidthAndKeepsHalfHeight() {
        // Too tall for a quarter, so the first press resizes.
        let frames = press(.bottomRight, 3, from: CGRect(x: 300, y: 300, width: 500, height: 500))
        XCTAssertEqual(frames.map(\.width), [721, 961, 481])
        XCTAssertEqual(frames.map(\.height), [438, 438, 438])
        XCTAssertTrue(frames.allSatisfy { $0.maxX == screen.maxX && $0.maxY == screen.maxY })
    }

    func testTopCycles() {
        XCTAssertEqual(Cycle.nextStep(for: .topHalf, window: frame(.topHalf, fraction: 0), screen: screen, last: nil), 2)
        XCTAssertEqual(Cycle.nextStep(for: .bottomHalf, window: frame(.bottomHalf, fraction: 2), screen: screen, last: nil), 1)
    }

    func testSmallWindowSlidesFirstThenCyclesWithoutSlidingAgain() {
        let frames = press(.leftHalf, 5, from: CGRect(x: 200, y: 200, width: 600, height: 400))
        XCTAssertEqual(frames, [
            CGRect(x: 0, y: 200, width: 600, height: 400),
            frame(.leftHalf, fraction: 0), frame(.leftHalf, fraction: 1), frame(.leftHalf, fraction: 2),
            frame(.leftHalf, fraction: 0),
        ])
    }

    func testRightAndBottomSlideAgainstTheirEdge() {
        let window = CGRect(x: 200, y: 200, width: 600, height: 300)
        XCTAssertEqual(press(.rightHalf, 1, from: window), [CGRect(x: 841, y: 200, width: 600, height: 300)])
        XCTAssertEqual(press(.topHalf, 1, from: window), [CGRect(x: 200, y: 25, width: 600, height: 300)])
        XCTAssertEqual(press(.bottomHalf, 1, from: window), [CGRect(x: 200, y: 600, width: 600, height: 300)])
    }

    func testSmallWindowSlidesIntoTheCorner() {
        let window = CGRect(x: 200, y: 200, width: 500, height: 300)
        XCTAssertEqual(press(.bottomRight, 2, from: window),
                       [CGRect(x: 941, y: 600, width: 500, height: 300), frame(.bottomRight, fraction: 0)])
        XCTAssertEqual(press(.topLeft, 1, from: window), [CGRect(x: 0, y: 25, width: 500, height: 300)])
    }

    func testSlideKeepsAPartlyOffScreenWindowOnScreen() {
        let window = CGRect(x: 300, y: 700, width: 600, height: 400)
        XCTAssertEqual(press(.leftHalf, 1, from: window), [CGRect(x: 0, y: 500, width: 600, height: 400)])
    }

    func testLargeWindowGoesStraightToHalf() {
        let wide = CGRect(x: 100, y: 100, width: 900, height: 500)
        XCTAssertEqual(press(.leftHalf, 2, from: wide), [frame(.leftHalf, fraction: 0), frame(.leftHalf, fraction: 1)])
        XCTAssertEqual(press(.rightHalf, 1, from: screen), [frame(.rightHalf, fraction: 0)])
        XCTAssertEqual(press(.topLeft, 1, from: screen), [frame(.topLeft, fraction: 0)])
    }

    func testWindowAlreadyAgainstTheEdgeGoesToHalf() {
        let slid = CGRect(x: 0, y: 200, width: 600, height: 400)
        XCTAssertEqual(Cycle.nextStep(for: .leftHalf, window: slid, screen: screen, last: nil), 1)
    }

    func testNearlyHalfSizedWindowSkipsTheSlide() {
        let nearlyHalf = CGRect(x: 300, y: 30, width: 710, height: 860)
        XCTAssertNil(Cycle.target(for: .leftHalf, step: 0, window: nearlyHalf, screen: screen))
        XCTAssertEqual(press(.leftHalf, 1, from: nearlyHalf), [frame(.leftHalf, fraction: 0)])
    }

    func testFixedStepWhenCyclingIsOff() {
        XCTAssertEqual(Cycle.fixedStep(for: .leftHalf), 1)
        XCTAssertEqual(Cycle.fixedStep(for: .bottomRight), 1)
        XCTAssertEqual(Cycle.fixedStep(for: .center), 0)
        XCTAssertEqual(Cycle.fixedStep(for: .maximize), 0)
        XCTAssertEqual(Cycle.target(for: .leftHalf, step: Cycle.fixedStep(for: .leftHalf),
                                    window: CGRect(x: 200, y: 200, width: 600, height: 400), screen: screen),
                       frame(.leftHalf, fraction: 0))
    }

    func testAdvancesWhenAppRoundedTheFrame() {
        // Terminal-style rounding: the app accepted a slightly different size than requested.
        let achieved = CGRect(x: 0, y: 25, width: 714, height: 868)
        let last = CycleRecord(action: .leftHalf, step: 1, screen: screen, achieved: achieved)
        XCTAssertEqual(Cycle.nextStep(for: .leftHalf, window: achieved, screen: screen, last: last), 2)
    }

    func testRecognisesCycleFrameWithoutHistory() {
        XCTAssertEqual(Cycle.nextStep(for: .leftHalf, window: frame(.leftHalf, fraction: 1),
                                      screen: screen, last: nil), 3)
    }

    func testOtherDirectionStartsOver() {
        let window = frame(.leftHalf, fraction: 0)
        let last = CycleRecord(action: .leftHalf, step: 1, screen: screen, achieved: window)
        XCTAssertEqual(Cycle.nextStep(for: .rightHalf, window: window, screen: screen, last: last), 1)
    }

    func testMovedWindowStartsOver() {
        let last = CycleRecord(action: .leftHalf, step: 2, screen: screen, achieved: frame(.leftHalf, fraction: 1))
        let moved = CGRect(x: 300, y: 100, width: 700, height: 500)
        XCTAssertEqual(Cycle.nextStep(for: .leftHalf, window: moved, screen: screen, last: last), 0)
    }

    func testOtherScreenStartsOver() {
        let other = CGRect(x: 1441, y: 0, width: 1920, height: 1055)
        let window = CGRect(x: 1500, y: 40, width: 900, height: 700)
        let last = CycleRecord(action: .leftHalf, step: 2, screen: screen, achieved: window)
        XCTAssertEqual(Cycle.nextStep(for: .leftHalf, window: window, screen: other, last: last), 0)
    }

    func testMaximizeAndNextDisplayDontCycle() {
        XCTAssertEqual(Cycle.nextStep(for: .maximize, window: screen, screen: screen, last: nil), 0)
        XCTAssertFalse(Cycle.supports(.maximize))
        XCTAssertFalse(Cycle.supports(.nextDisplay))
    }

    func testCenterThenTwoThirdsThenStays() {
        let frames = press(.center, 4, from: CGRect(x: 10, y: 600, width: 801, height: 500))
        let twoThirds = CGRect(x: 240, y: 171, width: 960, height: 583)
        XCTAssertEqual(frames, [CGRect(x: 320, y: 212, width: 801, height: 500), twoThirds, twoThirds, twoThirds])
    }

    func testCenterOnAlreadyCenteredWindowGrows() {
        let centered = Layout.centered(CGRect(x: 0, y: 0, width: 700, height: 400), in: screen)
        XCTAssertEqual(Cycle.nextStep(for: .center, window: centered, screen: screen, last: nil), 1)
    }

    func testCenterAtTwoThirdsWithoutHistoryStays() {
        let twoThirds = Cycle.target(for: .center, step: 1, window: .zero, screen: screen)!
        XCTAssertEqual(Cycle.nextStep(for: .center, window: twoThirds, screen: screen, last: nil), 1)
    }

    func testCenterAfterManualResizeStartsOver() {
        let twoThirds = Cycle.target(for: .center, step: 1, window: .zero, screen: screen)!
        let last = CycleRecord(action: .center, step: 1, screen: screen, achieved: twoThirds)
        let resized = CGRect(x: 100, y: 100, width: 600, height: 300)
        XCTAssertEqual(Cycle.nextStep(for: .center, window: resized, screen: screen, last: last), 0)
        XCTAssertEqual(Cycle.target(for: .center, step: 0, window: resized, screen: screen)!.size, resized.size)
    }
}
