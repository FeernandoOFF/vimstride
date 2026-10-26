import XCTest
@testable import MacNavigation

final class AccessibilityPreparationTests: XCTestCase {
    func testColdElectronTreeIsEnabledAndAllowedToPopulate() {
        var enabled = false
        var rendererReady = false
        AccessibilityPreparation.enableManualAccessibility(
            readEnabled: { enabled },
            setEnabled: { enabled = true; return true },
            isCancelled: { false },
            wait: { rendererReady = enabled }
        )
        XCTAssertTrue(enabled)
        XCTAssertTrue(rendererReady)
    }

    func testNativeAndAlreadyAccessibleAppsAreLeftAlone() {
        for enabled: Bool? in [nil, true] {
            AccessibilityPreparation.enableManualAccessibility(
                readEnabled: { enabled },
                setEnabled: { XCTFail("Must not change a native or already accessible app"); return true },
                isCancelled: { false },
                wait: { XCTFail("Must not delay an already available tree") }
            )
        }
    }

    func testRejectedActivationDoesNotDelayDiscovery() {
        AccessibilityPreparation.enableManualAccessibility(
            readEnabled: { false },
            setEnabled: { false },
            isCancelled: { false },
            wait: { XCTFail("Failed activation must fall through to normal discovery") }
        )
    }

    func testCancelledModeDoesNotEnableAccessibility() {
        AccessibilityPreparation.enableManualAccessibility(
            readEnabled: { false },
            setEnabled: { XCTFail("A cancelled mode must not enable the tree"); return true },
            isCancelled: { true },
            wait: { XCTFail("A cancelled mode must not wait") }
        )
    }

    func testWarmupStopsWhenModeIsCancelled() {
        var cancelled = false
        var waits = 0
        AccessibilityPreparation.enableManualAccessibility(
            readEnabled: { false },
            setEnabled: { true },
            isCancelled: { cancelled },
            wait: { waits += 1; cancelled = true }
        )
        XCTAssertEqual(waits, 1)
    }
}
