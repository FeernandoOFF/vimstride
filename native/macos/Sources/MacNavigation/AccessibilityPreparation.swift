import ApplicationServices
import Foundation

enum AccessibilityPreparation {
    // Electron deliberately leaves its renderer tree disabled until an assistive
    // client requests it. Use its documented opt-in, only when starting a mode.
    // Never toggle it off: another assistive client may also be using the tree.
    static func prepare(_ application: AXUIElement, isCancelled: () -> Bool) {
        enableManualAccessibility(
            readEnabled: { AccessibilityHints.attribute(application, "AXManualAccessibility") as? Bool },
            setEnabled: {
                AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
            },
            isCancelled: isCancelled,
            wait: { Thread.sleep(forTimeInterval: 0.05) }
        )
    }

    static func enableManualAccessibility(
        readEnabled: () -> Bool?,
        setEnabled: () -> Bool,
        isCancelled: () -> Bool,
        wait: () -> Void
    ) {
        // Unsupported attributes are normal in native apps. Do not request a
        // different screen-reader mode or impose startup delays on those apps.
        guard !isCancelled(), readEnabled() == false, !isCancelled(), setEnabled() else { return }
        // The setter returns before Chromium has rebuilt the renderer tree.
        // Allow a bounded warm-up before taking even the first window snapshot,
        // including when only native title-bar controls are initially present.
        for _ in 0..<5 {
            guard !isCancelled() else { return }
            wait()
        }
    }
}
