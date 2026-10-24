import ApplicationServices
import AppKit
import NavigationCore

private struct SmoothScrollSegment {
    let startedAt: TimeInterval
    let duration: TimeInterval
    let totalX: Double
    let totalY: Double
    var emittedX = 0.0
    var emittedY = 0.0
}

final class ScrollController: @unchecked Sendable {
    var status: (String) -> Void = { _ in }
    private var navigation: ScrollSession?
    private let worker = DispatchQueue(label: "vimstride.scroll-accessibility", qos: .userInitiated)
    private let overlay = ScrollOverlay()
    private var snapshot: AccessibleScrollSnapshot?
    private var cancellation = Cancellation()
    private var focusTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var targetPID: pid_t = 0
    private var session = 0
    private var selectedTargetID: Int?
    private var scrollTimer: Timer?
    private var scrollSegments: [SmoothScrollSegment] = []
    private var scrollPoint = CGPoint.zero
    private var remainderX = 0.0
    private var remainderY = 0.0
    private(set) var capturing = false

    static func easedProgress(_ progress: Double) -> Double {
        ScrollSession.easedProgress(progress)
    }

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.cancel(reason: "displayChanged") }
    }

    func begin() {
        if capturing { cancel(); return }
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        session += 1
        let generation = session
        targetPID = app.processIdentifier
        capturing = true
        snapshot = nil
        selectedTargetID = nil
        stopScrollAnimation()
        cancellation = Cancellation()
        let token = cancellation
        status("Finding scroll containers…")
        let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: screenTop - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
        let pointer = CGEvent(source: nil)?.location ?? .zero
        let pid = targetPID
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != self.targetPID {
                self.cancel(reason: "appChanged")
            }
        }
        worker.async { [weak self] in
            guard !token.isCancelled else { return }
            let result = AccessibilityScroll.discover(pid: pid, screenBounds: screens, pointer: pointer, isCancelled: { token.isCancelled })
            DispatchQueue.main.async {
                guard let self, self.capturing, self.session == generation, !token.isCancelled else { return }
                guard let result, !result.targets.isEmpty else { self.cancel(reason: "empty"); return }
                self.snapshot = result
                self.navigation = ScrollSession(targets: result.targets.map { Target(id: $0.id, x: $0.visibleBounds.minX, y: $0.visibleBounds.minY, width: $0.visibleBounds.width, height: $0.visibleBounds.height) }, preferredID: result.preferredTargetID)
                self.updateSelection()
                self.status("Scroll · H/J/K/L · Shift to dash · U/D half page · Tab to switch · Escape exits")
            }
        }
    }

    func cancel(reason: String = "cancelled") {
        guard capturing else { return }
        cancellation.cancel()
        capturing = false
        focusTimer?.invalidate()
        focusTimer = nil
        stopScrollAnimation()
        selectedTargetID = nil
        overlay.hide()
        snapshot = nil
        navigation = nil
        switch reason {
        case "empty": status("No accessible scroll containers found")
        case "stale", "appChanged", "displayChanged": status("Window changed. Start scrolling again.")
        case "actionFailed": status("The app did not accept scrolling. Try another container.")
        default: status("Ready")
        }
    }

    func key(_ value: String, dash: Bool = false) {
        guard capturing else { return }
        switch value {
        case "ESCAPE": cancel()
        case "NEXT": navigation?.cycle(); updateSelection()
        case "PREVIOUS": navigation?.cycle(backward: true); updateSelection()
        case "1", "2", "3", "4", "5", "6", "7", "8", "9": navigation?.select(index: Int(value)! - 1); updateSelection()
        default:
            guard let navigation, let snapshot, let id = selectedTargetID,
                  let target = snapshot.targets.first(where: { $0.id == id }) else { return }
            let direction: Direction
            switch value {
            case "LEFT": direction = .left
            case "RIGHT": direction = .right
            case "UP", "HALF_UP", "TOP": direction = .up
            case "DOWN", "HALF_DOWN", "BOTTOM": direction = .down
            default: return
            }
            var delta = navigation.delta(direction, halfPage: value.hasPrefix("HALF"), dash: dash)
            if value == "TOP" || value == "BOTTOM" { delta = Vector(0, value == "TOP" ? -5000 : 5000) }
            let scrollDelta = delta
            let cancellation = cancellation, generation = session
            worker.async { [weak self] in
                guard !cancellation.isCancelled else { return }
                let result = AccessibilityScroll.validate(target, snapshot: snapshot, isCancelled: { cancellation.isCancelled })
                DispatchQueue.main.async {
                    guard let self, self.session == generation, !cancellation.isCancelled else { return }
                    if result == "ready", self.selectedTargetID == id {
                        self.enqueueScroll(target: target, contentX: scrollDelta.x, contentY: scrollDelta.y, durationMillis: value.hasPrefix("HALF") ? 220 : 160)
                    } else if result != "ready" { self.cancel(reason: result) }
                }
            }
        }
    }
    private func updateSelection() {
        guard let navigation, let snapshot else { return }
        let id = navigation.selected.id
        if selectedTargetID != id { stopScrollAnimation() }
        selectedTargetID = id
        let regions = navigation.targets.enumerated().compactMap { index, target -> OverlayScrollRegion? in
            guard let native = snapshot.targets.first(where: { $0.id == target.id }) else { return nil }
            return OverlayScrollRegion(id: target.id, bounds: native.visibleBounds, number: index + 1, count: navigation.targets.count)
        }
        overlay.show(regions, selectedID: id)
    }

    private func enqueueScroll(
        target: AccessibleScrollTarget,
        contentX: Double,
        contentY: Double,
        durationMillis: Double
    ) {
        scrollPoint = CGPoint(x: target.visibleBounds.midX, y: target.visibleBounds.midY)
        scrollSegments.append(SmoothScrollSegment(
            startedAt: ProcessInfo.processInfo.systemUptime,
            duration: durationMillis / 1000.0,
            totalX: contentX,
            totalY: contentY
        ))
        guard scrollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.scrollFrame() }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }

    private func scrollFrame() {
        guard capturing, selectedTargetID != nil else { stopScrollAnimation(); return }
        let now = ProcessInfo.processInfo.systemUptime
        var x = 0.0
        var y = 0.0
        var remaining: [SmoothScrollSegment] = []
        for var segment in scrollSegments {
            let progress = min(1, (now - segment.startedAt) / segment.duration)
            let eased = Self.easedProgress(progress)
            let targetX = segment.totalX * eased
            let targetY = segment.totalY * eased
            x += targetX - segment.emittedX
            y += targetY - segment.emittedY
            segment.emittedX = targetX
            segment.emittedY = targetY
            if progress < 1 { remaining.append(segment) }
        }
        scrollSegments = remaining
        x += remainderX; y += remainderY
        let wholeX = x.rounded(.towardZero), wholeY = y.rounded(.towardZero)
        remainderX = x - wholeX; remainderY = y - wholeY
        if wholeX == 0, wholeY == 0 {
            if scrollSegments.isEmpty { stopScrollAnimation() }
            return
        }
        guard let event = AccessibilityScroll.scrollEvent(at: scrollPoint, contentX: wholeX, contentY: wholeY) else {
            cancel(reason: "actionFailed")
            return
        }
        event.post(tap: .cghidEventTap)
        if scrollSegments.isEmpty { stopScrollAnimation() }
    }

    private func stopScrollAnimation() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        scrollSegments.removeAll()
        remainderX = 0; remainderY = 0
    }
    deinit { if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }; focusTimer?.invalidate(); scrollTimer?.invalidate(); cancellation.cancel() }
}
