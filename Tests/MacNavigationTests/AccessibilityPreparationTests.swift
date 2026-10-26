import XCTest
@testable import MacNavigation

final class AccessibilityPreparationTests: XCTestCase {
    func testGeckoUsesEnhancedAccessibilityEvenWithoutReadableActivationAttribute() {
        for initial: Bool? in [false, nil] {
            var writes: [String] = []
            var waits = 0
            AccessibilityPreparation.prepare(
                isGecko: true,
                readEnabled: { XCTAssertEqual($0, "AXEnhancedUserInterface"); return initial },
                setEnabled: { writes.append($0); return true },
                isCancelled: { false },
                wait: { waits += 1 }
            )
            XCTAssertEqual(writes, ["AXEnhancedUserInterface"])
            XCTAssertEqual(waits, 5)
        }
    }

    func testNonGeckoAppsOnlyUseManualAccessibility() {
        for initial: Bool? in [false, nil, true] {
            var writes: [String] = []
            AccessibilityPreparation.prepare(
                isGecko: false,
                readEnabled: { XCTAssertEqual($0, "AXManualAccessibility"); return initial },
                setEnabled: { writes.append($0); return true },
                isCancelled: { false },
                wait: {}
            )
            XCTAssertEqual(writes, initial == false ? ["AXManualAccessibility"] : [])
        }
    }

    func testAlreadyEnabledAndCancelledGeckoAppsAreLeftAlone() {
        for cancelled in [false, true] {
            AccessibilityPreparation.prepare(
                isGecko: true,
                readEnabled: { _ in cancelled ? false : true },
                setEnabled: { _ in XCTFail("Must not reactivate"); return true },
                isCancelled: { cancelled },
                wait: { XCTFail("Must not wait") }
            )
        }
    }

    func testColdElectronTreeIsEnabledAndAllowedToPopulate() {
        var enabled = false
        var rendererReady = false
        AccessibilityPreparation.enableAccessibility(
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
            AccessibilityPreparation.enableAccessibility(
                readEnabled: { enabled },
                setEnabled: { XCTFail("Must not change a native or already accessible app"); return true },
                isCancelled: { false },
                wait: { XCTFail("Must not delay an already available tree") }
            )
        }
    }

    func testRejectedActivationDoesNotDelayDiscovery() {
        AccessibilityPreparation.enableAccessibility(
            readEnabled: { false },
            setEnabled: { false },
            isCancelled: { false },
            wait: { XCTFail("Failed activation must fall through to normal discovery") }
        )
    }

    func testCancelledModeDoesNotEnableAccessibility() {
        AccessibilityPreparation.enableAccessibility(
            readEnabled: { false },
            setEnabled: { XCTFail("A cancelled mode must not enable the tree"); return true },
            isCancelled: { true },
            wait: { XCTFail("A cancelled mode must not wait") }
        )
    }

    func testWarmupStopsWhenModeIsCancelled() {
        var cancelled = false
        var waits = 0
        AccessibilityPreparation.enableAccessibility(
            readEnabled: { false },
            setEnabled: { true },
            isCancelled: { cancelled },
            wait: { waits += 1; cancelled = true }
        )
        XCTAssertEqual(waits, 1)
    }
}
