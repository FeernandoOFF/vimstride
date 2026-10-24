import ApplicationServices
import AppKit
import Foundation

let hintMouseEventTag: Int64 = 0x4B4E4849

struct AccessibleHintTarget {
    let id: Int
    let element: AXUIElement
    let bounds: CGRect
    let visibleBounds: CGRect
    let role: String
    let supportsPress: Bool
}

struct AccessibleHintSnapshot {
    let pid: pid_t
    let window: AXUIElement
    let windowBounds: CGRect
    let targets: [AccessibleHintTarget]
    let partial: Bool
}

enum AccessibilityHints {
    private static let clickDelivery = ClickDelivery()
    static func releasePendingClicks() { clickDelivery.finish() }
    static func clickEvents(at point: CGPoint) -> (move: CGEvent, down: CGEvent, up: CGEvent)? {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ), let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ), let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return nil }
        move.flags = []
        down.flags = []
        up.flags = []
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        move.setIntegerValueField(.eventSourceUserData, value: hintMouseEventTag)
        down.setIntegerValueField(.eventSourceUserData, value: hintMouseEventTag)
        up.setIntegerValueField(.eventSourceUserData, value: hintMouseEventTag)
        return (move, down, up)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func bounds(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func focusedWindow(_ app: AXUIElement) -> AXUIElement? {
        guard let value = attribute(app, kAXFocusedWindowAttribute) ?? attribute(app, kAXMainWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    // Called only on the AX worker queue, never from the latency-sensitive event tap.
    static func discover(pid: pid_t, screenBounds: [CGRect], focusOnly: Bool = false, isCancelled: () -> Bool = { false }) -> AccessibleHintSnapshot? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let window = focusedWindow(app), let windowBounds = bounds(window) else { return nil }
        let deadline = Date().addingTimeInterval(1.5)
        var stack: [(AXUIElement, CGRect)] = [(window, windowBounds)]
        var visited: [CFHashCode: [AXUIElement]] = [:]
        var visitedCount = 0
        var rectangles = Set<String>()
        var targets: [AccessibleHintTarget] = []
        let fallbackRoles: Set<String> = [NSAccessibility.Role.link.rawValue, kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]

        while let (element, clip) = stack.popLast() {
            if isCancelled() || Date() > deadline || visitedCount >= 2500 || targets.count >= 500 { break }
            let hash = CFHash(element)
            if visited[hash, default: []].contains(where: { CFEqual($0, element) }) { continue }
            visited[hash, default: []].append(element)
            visitedCount += 1
            if (attribute(element, "AXHidden") as? Bool) == true { continue }
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            let frame = bounds(element)
            let visible = frame?.intersection(clip)
            let enabled = (attribute(element, kAXEnabledAttribute) as? Bool) != false

            if enabled, let frame, let visible, !visible.isNull, visible.width >= 3, visible.height >= 3,
               screenBounds.contains(where: { $0.contains(CGPoint(x: visible.midX, y: visible.midY)) }) {
                var actions: CFArray?
                AXUIElementCopyActionNames(element, &actions)
                let supportsPress = (actions as? [String] ?? []).contains(kAXPressAction)
                var focusSettable: DarwinBoolean = false
                AXUIElementIsAttributeSettable(element, kAXFocusedAttribute as CFString, &focusSettable)
                if focusOnly ? focusSettable.boolValue : (supportsPress || fallbackRoles.contains(role)) {
                    let key = "\(Int(visible.minX.rounded())):\(Int(visible.minY.rounded())):\(Int(visible.width.rounded())):\(Int(visible.height.rounded()))"
                    if rectangles.insert(key).inserted {
                        targets.append(AccessibleHintTarget(id: targets.count, element: element, bounds: frame, visibleBounds: visible, role: role, supportsPress: supportsPress))
                    }
                }
            }

            let childClip = role == kAXScrollAreaRole ? (visible ?? clip) : clip
            if childClip.isNull || childClip.isEmpty { continue }
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            stack.append(contentsOf: children.reversed().map { ($0, childClip) })
        }
        return AccessibleHintSnapshot(pid: pid, window: window, windowBounds: windowBounds, targets: targets, partial: !stack.isEmpty || Date() > deadline)
    }

    static func isCurrent(_ snapshot: AccessibleHintSnapshot) -> Bool {
        let system = AXUIElementCreateSystemWide()
        guard let focusedApp = attribute(system, kAXFocusedApplicationAttribute), CFGetTypeID(focusedApp) == AXUIElementGetTypeID() else { return false }
        var pid: pid_t = 0
        AXUIElementGetPid(focusedApp as! AXUIElement, &pid)
        guard pid == snapshot.pid,
              let window = focusedWindow(AXUIElementCreateApplication(pid)), CFEqual(window, snapshot.window),
              let frame = bounds(window), frame == snapshot.windowBounds else { return false }
        return true
    }

    static func isFrontmostApplication(pid expectedPID: pid_t) -> Bool {
        let system = AXUIElementCreateSystemWide()
        guard let focusedApp = attribute(system, kAXFocusedApplicationAttribute),
              CFGetTypeID(focusedApp) == AXUIElementGetTypeID() else { return false }
        var focusedPID: pid_t = 0
        AXUIElementGetPid(focusedApp as! AXUIElement, &focusedPID)
        return focusedPID == expectedPID
    }

    static func activate(_ target: AccessibleHintTarget, snapshot: AccessibleHintSnapshot, action: HintAction = .click, isCancelled: () -> Bool) -> String {
        let point = CGPoint(x: target.visibleBounds.midX, y: target.visibleBounds.midY)
        guard AXIsProcessTrusted(), isFrontmostApplication(pid: snapshot.pid),
              point.x.isFinite, point.y.isFinite, !isCancelled() else { return "stale" }

        if action == .focus {
            guard isCurrent(snapshot), let frame = bounds(target.element), frame == target.bounds, !isCancelled() else { return "stale" }
            return AXUIElementSetAttributeValue(target.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success ? "focused" : "actionFailed"
        }

        // A completed label is pointer-oriented: always use the coordinate
        // captured when the overlay was built. Re-checking the AX element here
        // caused false stale results in web/Electron apps while their trees were
        // updating, dismissing the overlay before any pointer event was posted.
        if let events = clickEvents(at: point) {
            guard !isCancelled() else { return "stale" }
            // Move the system cursor first, then deliver a move event to the
            // target process. CGWarp changes the visible cursor without
            // generating an event, so both operations are intentional.
            _ = CGWarpMouseCursorPosition(point)
            events.move.post(tap: .cgSessionEventTap)
            // Give Chromium/WebKit several rendering frames to update hover
            // and hit-testing state before the first and only click.
            Thread.sleep(forTimeInterval: 0.060)
            guard !isCancelled() else { return "stale" }
            guard isFrontmostApplication(pid: snapshot.pid) else { return "stale" }
            if action == .rightClick { events.down.type = .rightMouseDown; events.up.type = .rightMouseUp; events.down.setIntegerValueField(.mouseEventButtonNumber, value: 1); events.up.setIntegerValueField(.mouseEventButtonNumber, value: 1) }
            if action == .commandClick { events.down.flags = [.maskCommand]; events.up.flags = [.maskCommand] }
            guard clickDelivery.begin(down: events.down, up: events.up, isCancelled: isCancelled) else { return "stale" }
            // Match the conservative click duration used by established macOS
            // automation tools; very short synthetic clicks are inconsistently
            // recognized by some Chromium/Electron controls.
            Thread.sleep(forTimeInterval: 0.200)
            clickDelivery.finish()
            return "clicked"
        }

        // These semantic paths are construction fallbacks only. Never combine
        // them with a posted coordinate click, which could activate twice.
        guard isCurrent(snapshot),
              let currentBounds = bounds(target.element), currentBounds == target.bounds,
              (attribute(target.element, kAXEnabledAttribute) as? Bool) != false else { return "stale" }
        if target.supportsPress {
            let result = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
            if result == .success { return "activated" }
            // A timeout is ambiguous: never issue a second click that might duplicate an action.
            if result != .actionUnsupported { return "actionFailed" }
        }
        if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(target.role) {
            guard !isCancelled() else { return "stale" }
            let result = AXUIElementSetAttributeValue(target.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if result == .success { return "focused" }
            if result == .cannotComplete { return "actionFailed" }
        }
        return "actionFailed"
    }
}
