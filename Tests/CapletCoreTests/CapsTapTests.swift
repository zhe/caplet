import Foundation
import XCTest
@testable import CapletCore

final class CapsTapTests: XCTestCase {
    func testQuickPressAloneIsATap() {
        var tap = CapsTap()
        tap.pressed(at: 10)
        XCTAssertTrue(tap.isHeld)
        XCTAssertTrue(tap.released(at: 10.15))
        XCTAssertFalse(tap.isHeld)
    }

    func testPressingAnotherKeyMakesItAShortcut() {
        var tap = CapsTap()
        tap.pressed(at: 10)
        tap.otherKeyPressed()
        XCTAssertFalse(tap.released(at: 10.1))
    }

    func testLongHoldWithoutKeysDoesNothing() {
        var tap = CapsTap()
        tap.pressed(at: 10)
        XCTAssertFalse(tap.released(at: 10 + CapsTap.maxTapDuration + 0.01))
    }

    func testAutoRepeatDoesNotRestartTheTimer() {
        var tap = CapsTap()
        tap.pressed(at: 10)
        tap.pressed(at: 10.4)
        tap.pressed(at: 10.8)
        XCTAssertFalse(tap.released(at: 10.9))
    }

    func testOtherKeysBeforePressingDontCount() {
        var tap = CapsTap()
        tap.otherKeyPressed()
        tap.pressed(at: 10)
        XCTAssertTrue(tap.released(at: 10.1))
    }

    func testEachPressStartsClean() {
        var tap = CapsTap()
        tap.pressed(at: 10)
        tap.otherKeyPressed()
        _ = tap.released(at: 10.1)
        tap.pressed(at: 11)
        XCTAssertTrue(tap.released(at: 11.1))
    }

    func testReleaseWithoutPressIsNotATap() {
        var tap = CapsTap()
        XCTAssertFalse(tap.released(at: 10))
    }

    func testResetForgetsAPressInProgress() {
        var tap = CapsTap()
        tap.pressed(at: 10)
        tap.reset()
        XCTAssertFalse(tap.isHeld)
        XCTAssertFalse(tap.released(at: 10.1))
    }
}
