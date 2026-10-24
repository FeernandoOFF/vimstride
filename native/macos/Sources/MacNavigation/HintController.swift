import ApplicationServices
import AppKit
import NavigationCore

final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}
enum HintAction { case click, rightClick, commandClick, focus }

final class HintController: @unchecked Sendable {
    var status: (String) -> Void = { _ in }
    var clicked: () -> Void = {}
    var completed: () -> Void = {}
    var labelSize = 13
    var onSelection: ((Int, HintAction) -> Void)?
    private let worker = DispatchQueue(label: "vimstride.accessibility", qos: .userInitiated)
    private let overlay = HintOverlay()
    private var snapshot: AccessibleHintSnapshot?
    private var token = Cancellation()
    private var focusTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var targetPID: pid_t = 0
    private var generation = 0
    var generationID: Int { generation }
    private var selecting = false
    private var focusOnly = false
    private(set) var capturing = false
    private(set) var session: HintSession?

    init() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.cancel(reason: "Display changed") }
    }
    func begin(focusOnly: Bool = false) {
        if capturing { cancel(); return }
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        generation += 1
        let current = generation
        targetPID = app.processIdentifier
        capturing = true; selecting = false; snapshot = nil; session = nil; self.focusOnly = focusOnly
        token = Cancellation()
        let cancellation = token
        status(focusOnly ? "Finding focusable controls…" : "Finding clickable controls…")
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        let pid = targetPID
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != self.targetPID { self.cancel(reason: "Application changed") }
        }
        worker.async { [weak self] in
            guard !cancellation.isCancelled else { return }
            let result = AccessibilityHints.discover(pid: pid, screenBounds: screens, focusOnly: focusOnly, isCancelled: { cancellation.isCancelled })
            DispatchQueue.main.async {
                guard let self, self.capturing, self.generation == current, !cancellation.isCancelled else { return }
                guard let result, !result.targets.isEmpty else { self.cancel(reason: "No accessible controls found. Try pointer movement."); return }
                self.snapshot = result
                self.session = HintSession(targets: result.targets.map { Target(id: $0.id, x: $0.visibleBounds.minX, y: $0.visibleBounds.minY, width: $0.visibleBounds.width, height: $0.visibleBounds.height) })
                self.render()
                self.status("\(result.targets.count) targets\(result.partial ? " (scan limit)" : "") · type a label, Tab to browse, Return to \(focusOnly ? "focus" : "click")")
            }
        }
    }
    func cancel(reason: String = "Ready") {
        guard capturing else { return }
        token.cancel()
        AccessibilityHints.releasePendingClicks()
        capturing = false; selecting = false
        focusTimer?.invalidate(); focusTimer = nil
        overlay.hide(); snapshot = nil; session = nil
        completed(); status(reason)
    }
    func key(_ value: String) {
        guard capturing else { return }
        if value == "ESCAPE" { cancel(); return }
        guard !selecting else { return }
        switch value {
        case "ESCAPE": cancel()
        case "SIZE_UP": labelSize = min(33, labelSize + 2); render()
        case "SIZE_DOWN": labelSize = max(9, labelSize - 2); render()
        case "NEXT": session?.cycle(); render()
        case "PREVIOUS": session?.cycle(backward: true); render()
        case "BACKSPACE": session?.backspace(); render()
        case "CLICK", "RIGHT_CLICK", "COMMAND_CLICK", "FOCUS":
            guard let id = session?.focusedID else { return }
            let action: HintAction = focusOnly || value == "FOCUS" ? .focus : value == "RIGHT_CLICK" ? .rightClick : value == "COMMAND_CLICK" ? .commandClick : .click
            select(id, action: action)
        default:
            guard value.count == 1, let character = value.first else { return }
            if let result = session?.type(character), result.accepted {
                render()
                if let id = result.selected { select(id, action: focusOnly ? .focus : .click) }
            }
        }
    }
    private func render() {
        guard let session, let snapshot else { return }
        overlay.show(session.visible.compactMap { label in
            guard let target = snapshot.targets.first(where: { $0.id == label.target.id }) else { return nil }
            return OverlayHint(bounds: target.visibleBounds, label: label.text, focused: target.id == session.focusedID)
        }, prefix: session.prefix, fontSize: CGFloat(labelSize))
    }
    private func select(_ id: Int, action: HintAction) {
        selecting = true
        onSelection?(id, action)
    }
    func activate(_ id: Int, action: HintAction) {
        guard capturing, let snapshot, let target = snapshot.targets.first(where: { $0.id == id }) else { return }
        overlay.hide()
        let cancellation = token, current = generation
        worker.async { [weak self] in
            guard !cancellation.isCancelled else { return }
            let result = AccessibilityHints.activate(target, snapshot: snapshot, action: action, isCancelled: { cancellation.isCancelled })
            DispatchQueue.main.async {
                guard let self, self.generation == current, !cancellation.isCancelled else { return }
                if result == "clicked" || result == "activated" { self.clicked() }
                self.cancel(reason: result == "focused" ? "Control focused" : result == "clicked" || result == "activated" ? "Ready" : "Target changed or unavailable; try again")
            }
        }
    }
    deinit { if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }; focusTimer?.invalidate(); token.cancel() }
}
