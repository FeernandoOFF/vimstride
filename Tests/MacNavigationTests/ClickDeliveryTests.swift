import XCTest
import ApplicationServices
@testable import MacNavigation

final class ClickDeliveryTests: XCTestCase {
    func testShutdownReleaseIsImmediateAndIdempotent() {
        var posted: [CGEventType] = []
        let delivery = ClickDelivery { posted.append($0.type) }
        let events = AccessibilityHints.clickEvents(at: .zero)!
        XCTAssertTrue(delivery.begin(down: events.down, up: events.up, isCancelled: { false }))
        XCTAssertEqual(posted, [.leftMouseDown])
        // Main-thread cancellation/termination need not wait for worker delay.
        delivery.finish()
        XCTAssertEqual(posted, [.leftMouseDown, .leftMouseUp])
        // A worker finishing later must not post a second mouse-up.
        delivery.finish()
        XCTAssertEqual(posted, [.leftMouseDown, .leftMouseUp])
    }
    func testCancelledWorkerCannotPressAfterShutdown() {
        var posted: [CGEventType] = []
        let delivery = ClickDelivery { posted.append($0.type) }
        let events = AccessibilityHints.clickEvents(at: .zero)!
        delivery.finish()
        XCTAssertFalse(delivery.begin(down: events.down, up: events.up, isCancelled: { true }))
        XCTAssertTrue(posted.isEmpty)
    }
    func testOverlappingDownCannotOverwriteRequiredUp() {
        var posted: [CGEventType] = []
        let delivery = ClickDelivery { posted.append($0.type) }
        let events = AccessibilityHints.clickEvents(at: .zero)!
        XCTAssertTrue(delivery.begin(down: events.down, up: events.up, isCancelled: { false }))
        XCTAssertFalse(delivery.begin(down: events.down, up: events.up, isCancelled: { false }))
        delivery.finish()
        XCTAssertEqual(posted, [.leftMouseDown, .leftMouseUp])
    }
}
