import ApplicationServices
import AppKit
import Foundation

let scrollMouseEventTag: Int64 = 0x4B4E5343

struct AccessibleScrollTarget {
    let id: Int
    let element: AXUIElement
    let bounds: CGRect
    let visibleBounds: CGRect
}

struct AccessibleScrollSnapshot {
    let pid: pid_t
    let window: AXUIElement
    let windowBounds: CGRect
    let targets: [AccessibleScrollTarget]
    let preferredTargetID: Int
    let partial: Bool
}

enum AccessibilityScroll {
    private static let heuristicRoles: Set<String> = [
        kAXGroupRole,
        kAXListRole,
        kAXTableRole,
        kAXOutlineRole,
        "AXLayoutArea",
    ]

    static func isScrollCandidate(
        role: String,
        frame: CGRect,
        childFrames: [CGRect],
        childCount: Int,
        visibleChildCount: Int?,
        hasScrollbar: Bool
    ) -> Bool {
        if role == kAXScrollAreaRole { return true }
        if frame.width < 80 || frame.height < 80 { return false }
        if role == "AXWebArea" { return true }
        if hasScrollbar { return true }

        guard heuristicRoles.contains(role) else { return false }
        if let visibleChildCount, childCount > visibleChildCount { return true }
        let combinedBounds = childFrames.reduce(Optional<CGRect>.none) { partial, child in
            guard child.width > 0, child.height > 0 else { return partial }
            return partial?.union(child) ?? child
        }
        guard let contentBounds = combinedBounds else { return false }
        let margin: CGFloat = 24
        return contentBounds.minX < frame.minX - margin || contentBounds.maxX > frame.maxX + margin ||
            contentBounds.minY < frame.minY - margin || contentBounds.maxY > frame.maxY + margin
    }

    static func discover(pid: pid_t, screenBounds: [CGRect], pointer: CGPoint, isCancelled: () -> Bool = { false }) -> AccessibleScrollSnapshot? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let window = AccessibilityHints.focusedWindow(app),
              let windowBounds = AccessibilityHints.bounds(window) else { return nil }
        let deadline = Date().addingTimeInterval(1.5)
        var stack: [(AXUIElement, CGRect)] = [(window, windowBounds)]
        var visited: [CFHashCode: [AXUIElement]] = [:]
        var rectangles = Set<String>()
        var targets: [AccessibleScrollTarget] = []
        var visitedCount = 0

        while let (element, clip) = stack.popLast() {
            if isCancelled() || Date() > deadline || visitedCount >= 2500 || targets.count >= 64 { break }
            let hash = CFHash(element)
            if visited[hash, default: []].contains(where: { CFEqual($0, element) }) { continue }
            visited[hash, default: []].append(element)
            visitedCount += 1
            if (AccessibilityHints.attribute(element, "AXHidden") as? Bool) == true { continue }
            let role = AccessibilityHints.attribute(element, kAXRoleAttribute) as? String ?? ""
            let frame = AccessibilityHints.bounds(element)
            let visible = frame?.intersection(clip)
            let enabled = (AccessibilityHints.attribute(element, kAXEnabledAttribute) as? Bool) != false
            let children = AccessibilityHints.attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            let inspectForScrolling = role == kAXScrollAreaRole || role == "AXWebArea" || Self.heuristicRoles.contains(role)
            let visibleChildren = inspectForScrolling
                ? AccessibilityHints.attribute(element, kAXVisibleChildrenAttribute) as? [AXUIElement]
                : nil
            let childFrames = inspectForScrolling ? children.prefix(64).compactMap(AccessibilityHints.bounds) : []
            let hasScrollbar = inspectForScrolling && (
                AccessibilityHints.attribute(element, kAXVerticalScrollBarAttribute) != nil ||
                    AccessibilityHints.attribute(element, kAXHorizontalScrollBarAttribute) != nil
            )
            let candidate = frame.map {
                isScrollCandidate(
                    role: role,
                    frame: $0,
                    childFrames: childFrames,
                    childCount: children.count,
                    visibleChildCount: visibleChildren?.count,
                    hasScrollbar: hasScrollbar
                )
            } ?? false

            if candidate, enabled, let frame, let visible,
               !visible.isNull, visible.width >= 24, visible.height >= 24,
               screenBounds.contains(where: { $0.contains(CGPoint(x: visible.midX, y: visible.midY)) }) {
                let key = "\(Int(visible.minX.rounded())):\(Int(visible.minY.rounded())):\(Int(visible.width.rounded())):\(Int(visible.height.rounded()))"
                if rectangles.insert(key).inserted {
                    targets.append(AccessibleScrollTarget(
                        id: targets.count,
                        element: element,
                        bounds: frame,
                        visibleBounds: visible
                    ))
                }
            }

            let childClip = candidate ? (visible ?? clip) : clip
            if childClip.isNull || childClip.isEmpty { continue }
            stack.append(contentsOf: children.reversed().map { ($0, childClip) })
        }

        // Browsers and custom UI sometimes expose no AXScrollArea even though the
        // focused window accepts wheel events. Keep one safe window-level fallback.
        if targets.isEmpty {
            let visible = screenBounds.map { windowBounds.intersection($0) }
                .filter { !$0.isNull }
                .max { ($0.width * $0.height) < ($1.width * $1.height) }
            if let visible, visible.width >= 24, visible.height >= 24 {
                targets.append(AccessibleScrollTarget(id: 0, element: window, bounds: windowBounds, visibleBounds: visible))
            }
        }
        guard !targets.isEmpty else { return nil }

        let preferred = targets.filter { $0.visibleBounds.contains(pointer) }
            .min { ($0.visibleBounds.width * $0.visibleBounds.height) < ($1.visibleBounds.width * $1.visibleBounds.height) }
            ?? targets[0]
        return AccessibleScrollSnapshot(
            pid: pid,
            window: window,
            windowBounds: windowBounds,
            targets: targets,
            preferredTargetID: preferred.id,
            partial: !stack.isEmpty || Date() > deadline
        )
    }

    static func isCurrent(_ snapshot: AccessibleScrollSnapshot) -> Bool {
        let system = AXUIElementCreateSystemWide()
        guard let focusedApp = AccessibilityHints.attribute(system, kAXFocusedApplicationAttribute),
              CFGetTypeID(focusedApp) == AXUIElementGetTypeID() else { return false }
        var pid: pid_t = 0
        AXUIElementGetPid(focusedApp as! AXUIElement, &pid)
        guard pid == snapshot.pid,
              let window = AccessibilityHints.focusedWindow(AXUIElementCreateApplication(pid)),
              CFEqual(window, snapshot.window),
              let frame = AccessibilityHints.bounds(window), frame == snapshot.windowBounds else { return false }
        return true
    }

    static func scrollEvent(at point: CGPoint, contentX: Double, contentY: Double) -> CGEvent? {
        guard contentX.isFinite, contentY.isFinite else { return nil }
        let clamp: (Double) -> Int32 = { value in
            Int32(max(Double(Int32.min), min(Double(Int32.max), value.rounded())))
        }
        guard let event = CGEvent(
            scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState),
            units: .pixel,
            wheelCount: 2,
            wheel1: clamp(-contentY),
            wheel2: clamp(-contentX),
            wheel3: 0
        ) else { return nil }
        event.location = point
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: scrollMouseEventTag)
        return event
    }

    static func validate(
        _ target: AccessibleScrollTarget,
        snapshot: AccessibleScrollSnapshot,
        isCancelled: () -> Bool
    ) -> String {
        guard AXIsProcessTrusted(), !isCancelled(), isCurrent(snapshot),
              let currentBounds = AccessibilityHints.bounds(target.element), currentBounds == target.bounds else { return "stale" }
        return "ready"
    }
}
