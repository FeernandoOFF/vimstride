import XCTest
import AppKit
import ApplicationServices
import NavigationCore
@testable import MacNavigation

final class InputTests: XCTestCase {
    let hyper: CGEventFlags = [.maskCommand, .maskControl, .maskShift]
    @discardableResult func key(_ state: InputController, _ key: CGKeyCode, _ type: CGEventType, flags: CGEventFlags = []) -> Bool {
        let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: key, keyDown: type == .keyDown)!
        event.type = type; event.flags = flags
        return state.handle(type: type, event: event) != nil
    }
    func testOrdinaryKeysPassThroughInactive() {
        let state = InputController(postPointerEvents: false)
        for code: CGKeyCode in [4, 38, 40, 37, 49, 24, 27, 36, 48] {
            XCTAssertTrue(key(state, code, .keyDown)); XCTAssertTrue(key(state, code, .keyUp))
        }
        XCTAssertFalse(state.movement.active)
    }
    func testHyperActivationMovementAndRelease() {
        let state = InputController(postPointerEvents: false)
        key(state, 56, .flagsChanged, flags: hyper)
        XCTAssertTrue(state.movement.active); XCTAssertFalse(key(state, 4, .keyDown, flags: hyper))
        XCTAssertEqual(state.movement.vector, Vector(-1, 0))
        key(state, 56, .flagsChanged)
        XCTAssertEqual(state.movement, MovementState()); XCTAssertNil(state.pointerButtonDown)
        XCTAssertFalse(key(state, 4, .keyDown)); XCTAssertFalse(key(state, 4, .keyUp))
        XCTAssertTrue(key(state, 4, .keyDown)); XCTAssertTrue(key(state, 4, .keyUp))
    }
    func testDefaultSuperFGVShortcutsAreConsumed() {
        let state = InputController(postPointerEvents: false)
        for code: CGKeyCode in [3, 5, 9] {
            XCTAssertFalse(key(state, code, .keyDown, flags: hyper))
            XCTAssertFalse(key(state, code, .keyUp))
        }
        XCTAssertTrue(key(state, 3, .keyDown)); XCTAssertTrue(key(state, 3, .keyUp))
    }
    func testSpaceDragsAndRightClick() {
        let state = InputController(postPointerEvents: false)
        key(state, 56, .flagsChanged, flags: hyper)
        XCTAssertFalse(key(state, 49, .keyDown, flags: hyper)); XCTAssertEqual(state.pointerButtonDown, .left)
        XCTAssertFalse(key(state, 49, .keyDown, flags: hyper))
        state.moveCursor(dx: 5, dy: 0); XCTAssertEqual(state.lastMovementEventType, .leftMouseDragged)
        XCTAssertFalse(key(state, 49, .keyUp, flags: hyper)); XCTAssertNil(state.pointerButtonDown)
        state.moveCursor(dx: 5, dy: 0); XCTAssertEqual(state.lastMovementEventType, .mouseMoved)
        XCTAssertFalse(key(state, 15, .keyDown, flags: hyper)); XCTAssertEqual(state.pointerButtonDown, .right)
        state.moveCursor(dx: 0, dy: 5); XCTAssertEqual(state.lastMovementEventType, .rightMouseDragged)
        key(state, 56, .flagsChanged); XCTAssertNil(state.pointerButtonDown)
    }
    func testHookDisableClearsMovementAndDrag() {
        let state = InputController(postPointerEvents: false)
        key(state, 56, .flagsChanged, flags: hyper); key(state, 49, .keyDown, flags: hyper); key(state, 4, .keyDown, flags: hyper)
        let event = CGEvent(source: nil)!
        _ = state.handle(type: .tapDisabledByTimeout, event: event)
        XCTAssertEqual(state.movement, MovementState()); XCTAssertNil(state.pointerButtonDown)
    }
    func testSideSpecificActivationAndCustomDirection() throws {
        let state = InputController(postPointerEvents: false)
        var config = NavigationConfig(); config.bindings["free_mode"] = "right_option"; config.bindings["move_left"] = "a"
        state.configure(try config.validated())
        key(state, 58, .flagsChanged, flags: CGEventFlags(rawValue: 0x80020)); XCTAssertFalse(state.movement.active)
        key(state, 61, .flagsChanged, flags: CGEventFlags(rawValue: 0x80040)); XCTAssertTrue(state.movement.active)
        XCTAssertTrue(key(state, 4, .keyDown, flags: CGEventFlags(rawValue: 0x80040)))
        XCTAssertFalse(key(state, 0, .keyDown, flags: CGEventFlags(rawValue: 0x80040)))
        XCTAssertEqual(state.movement.vector, Vector(-1, 0))
    }
    func testRightSideSpeedModifiersDontRequireOption() {
        let state = InputController(postPointerEvents: false)
        key(state, 56, .flagsChanged, flags: hyper)
        key(state, 60, .flagsChanged, flags: CGEventFlags(rawValue: hyper.rawValue | 0x04))
        XCTAssertTrue(state.movement.fast)
        key(state, 62, .flagsChanged, flags: CGEventFlags(rawValue: hyper.rawValue | 0x04 | 0x2000))
        XCTAssertTrue(state.movement.precise)
    }
    func testReconfigureAndPauseReleaseHeldState() {
        let state = InputController(postPointerEvents: false)
        key(state, 56, .flagsChanged, flags: hyper); key(state, 49, .keyDown, flags: hyper)
        state.configure(NavigationConfig()); XCTAssertNil(state.pointerButtonDown); XCTAssertFalse(state.movement.active)
        state.setPaused(true); XCTAssertTrue(key(state, 4, .keyDown, flags: hyper))
    }
    func testSyntheticClickConstructionAndScrollGeometry() {
        let events = AccessibilityHints.clickEvents(at: CGPoint(x: 120, y: 80))!
        XCTAssertEqual(events.move.type, .mouseMoved); XCTAssertEqual(events.down.type, .leftMouseDown); XCTAssertEqual(events.up.type, .leftMouseUp)
        XCTAssertEqual(events.down.getIntegerValueField(.mouseEventClickState), 1)
        XCTAssertEqual(events.up.getIntegerValueField(.eventSourceUserData), hintMouseEventTag)
        let event = AccessibilityScroll.scrollEvent(at: .zero, contentX: 80, contentY: -120)!
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 120)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), -80)
        XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), scrollMouseEventTag)
        XCTAssertTrue(AccessibilityScroll.isScrollCandidate(role: "AXWebArea", frame: CGRect(x: 0, y: 0, width: 800, height: 600), childFrames: [], childCount: 0, visibleChildCount: nil, hasScrollbar: false))
        XCTAssertFalse(AccessibilityScroll.isScrollCandidate(role: "AXGroup", frame: CGRect(x: 0, y: 0, width: 300, height: 200), childFrames: [CGRect(x: 10, y: 10, width: 280, height: 180)], childCount: 1, visibleChildCount: 1, hasScrollbar: false))
    }
}
