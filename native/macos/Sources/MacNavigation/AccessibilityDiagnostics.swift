import AppKit
import ApplicationServices

enum AccessibilityDiagnostics {
    // Permission here applies to the diagnostic process's launch context, which
    // can differ from the background app. Print counts, never labels or content.
    static func run(pid: pid_t) -> Int32 {
        let trusted = AXIsProcessTrusted()
        print("Accessibility permission: \(trusted ? "granted" : "missing")")
        guard trusted else { return 3 }
        guard NSRunningApplication(processIdentifier: pid) != nil else {
            print("Target process is not running")
            return 2
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        func activationState(_ name: String) -> String {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(app, name as CFString, &value)
            return "result=\(result.rawValue), enabled=\((value as? Bool).map(String.init) ?? "unknown")"
        }
        let attributes = ["AXManualAccessibility", "AXEnhancedUserInterface"]
        for name in attributes { print("\(name) before: \(activationState(name))") }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
        let snapshot = AccessibilityHints.discover(pid: pid, screenBounds: screens)
        for name in attributes { print("\(name) after: \(activationState(name))") }
        guard let snapshot else {
            if let window = AccessibilityHints.focusedWindow(app) {
                let role = AccessibilityHints.attribute(window, kAXRoleAttribute) as? String ?? "unknown"
                print("Focused window role: \(role); window geometry unavailable")
            } else {
                print("Focused window: unavailable")
            }
            return 4
        }
        print("Clickable targets: \(snapshot.targets.count), partial: \(snapshot.partial)")
        for (role, targets) in Dictionary(grouping: snapshot.targets, by: \.role).sorted(by: { $0.key < $1.key }) {
            print("\(role): \(targets.count)")
        }
        return snapshot.targets.isEmpty ? 4 : 0
    }
}
