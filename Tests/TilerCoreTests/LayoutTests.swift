import Foundation
import XCTest
@testable import TilerCore

final class LayoutTests: XCTestCase {
    func testFlipConvertsBottomLeftToTopLeft() {
        // 1440x900 primary display with a 25pt menu bar: Cocoa visibleFrame starts at y=0, height 875.
        let cocoaVisible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(Layout.flip(cocoaVisible, primaryHeight: 900),
                       CGRect(x: 0, y: 25, width: 1440, height: 875))
    }

    func testFlipHandlesSecondaryDisplayAbovePrimary() {
        let cocoa = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        XCTAssertEqual(Layout.flip(cocoa, primaryHeight: 900),
                       CGRect(x: 0, y: -1080, width: 1920, height: 1080))
    }

    func testFlipIsItsOwnInverse() {
        let rect = CGRect(x: 12, y: 340, width: 800, height: 600)
        XCTAssertEqual(Layout.flip(Layout.flip(rect, primaryHeight: 1117), primaryHeight: 1117), rect)
    }

    func testHalvesCoverOddWidthsWithoutGaps() {
        let visible = CGRect(x: 100, y: 25, width: 1441, height: 875)
        let left = Layout.frame(for: .leftHalf, in: visible)!
        let right = Layout.frame(for: .rightHalf, in: visible)!
        XCTAssertEqual(left, CGRect(x: 100, y: 25, width: 720, height: 875))
        XCTAssertEqual(right, CGRect(x: 820, y: 25, width: 721, height: 875))
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(right.maxX, visible.maxX)
    }

    func testMaximizeFillsVisibleFrame() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        XCTAssertEqual(Layout.frame(for: .maximize, in: visible), visible)
        XCTAssertNil(Layout.frame(for: .nextDisplay, in: visible))
    }

    func testScreenIndexPicksLargestOverlap() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800),
                       CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        XCTAssertEqual(Layout.screenIndex(for: CGRect(x: 900, y: 0, width: 400, height: 300), in: screens), 1)
        XCTAssertEqual(Layout.screenIndex(for: CGRect(x: 700, y: 0, width: 400, height: 300), in: screens), 0)
    }

    func testScreenIndexFallsBackToNearestScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800),
                       CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        XCTAssertEqual(Layout.screenIndex(for: CGRect(x: 2500, y: 100, width: 200, height: 200), in: screens), 1)
        XCTAssertNil(Layout.screenIndex(for: .zero, in: []))
    }

    func testMoveKeepsProportionsAcrossDisplays() {
        let laptop = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let external = CGRect(x: 1440, y: -200, width: 2560, height: 1415)
        let leftHalf = Layout.frame(for: .leftHalf, in: laptop)!
        XCTAssertEqual(Layout.move(leftHalf, from: laptop, to: external),
                       CGRect(x: 1440, y: -200, width: 1280, height: 1415))
    }

    func testClampKeepsWindowInsideBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(Layout.clamp(CGRect(x: 900, y: -50, width: 300, height: 2000), to: bounds),
                       CGRect(x: 700, y: 0, width: 300, height: 800))
    }
}
