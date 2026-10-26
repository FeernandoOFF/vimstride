import ApplicationServices
import AppKit
import Foundation

enum AccessibilityPreparation {
    // Browser engines leave their renderer tree disabled until an assistive
    // client requests it. Request it only when starting a mode.
    // Never toggle it off: another assistive client may also be using the tree.
    static func prepare(_ application: AXUIElement, isCancelled: () -> Bool) {
        var pid: pid_t = 0
        AXUIElementGetPid(application, &pid)
        let bundleURL = NSRunningApplication(processIdentifier: pid)?.bundleURL
        let isGecko = bundleURL.map {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/MacOS/XUL").path)
        } ?? false
        prepare(
            isGecko: isGecko,
            readEnabled: { AccessibilityHints.attribute(application, $0) as? Bool },
            setEnabled: {
                AXUIElementSetAttributeValue(application, $0 as CFString, kCFBooleanTrue) == .success
            },
            isCancelled: isCancelled,
            wait: { Thread.sleep(forTimeInterval: 0.05) }
        )
    }

    static func prepare(
        isGecko: Bool,
        readEnabled: (String) -> Bool?,
        setEnabled: (String) -> Bool,
        isCancelled: () -> Bool,
        wait: () -> Void
    ) {
        // Gecko uses the enhanced-UI handshake, not Electron's manual one.
        // See accessible/mac/Platform.mm, GeckoNSApplication (a11y), in Mozilla.
        // Scope it to the Gecko runtime: setting it on arbitrary native or
        // Chromium apps can change their screen-reader behavior.
        let attribute = isGecko ? "AXEnhancedUserInterface" : "AXManualAccessibility"
        enableAccessibility(
            readEnabled: { readEnabled(attribute) },
            setEnabled: { setEnabled(attribute) },
            isCancelled: isCancelled,
            wait: wait,
            allowUnreadable: isGecko
        )
    }

    static func enableAccessibility(
        readEnabled: () -> Bool?,
        setEnabled: () -> Bool,
        isCancelled: () -> Bool,
        wait: () -> Void,
        allowUnreadable: Bool = false
    ) {
        // Unsupported attributes are normal in native apps. Only a positively
        // identified engine may opt in without a readable activation state.
        guard !isCancelled() else { return }
        let enabled = readEnabled()
        guard enabled == false || (enabled == nil && allowUnreadable),
              !isCancelled(), setEnabled() else { return }
        // The setter returns before the engine has rebuilt the renderer tree.
        // Allow a bounded warm-up before taking even the first window snapshot,
        // including when only native title-bar controls are initially present.
        for _ in 0..<5 {
            guard !isCancelled() else { return }
            wait()
        }
    }
}
