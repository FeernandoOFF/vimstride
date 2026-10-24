import AppKit
import ApplicationServices
import Carbon.HIToolbox
import NavigationCore

let freeMouseEventTag: Int64 = 0x4B4E4652

final class InputController: @unchecked Sendable {
    var onStatus: (String) -> Void = { _ in }
    var onClick: () -> Void = {}
    var onPermission: (Bool) -> Void = { _ in }
    let postPointerEvents: Bool
    private(set) var movement = MovementState()
    private(set) var pointerButtonDown: CGMouseButton?
    private(set) var lastMovementEventType: CGEventType?
    private(set) var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var bindings: [String: NativeBinding] = [:]
    private var config = NavigationConfig()
    private var heldDirections: [CGKeyCode: Direction] = [:]
    private var suppressedKeyUps = Set<CGKeyCode>()
    private var clickKey: CGKeyCode?
    private var clickModifier: String?
    private var moveTimer: Timer?
    private var permissionTimer: Timer?
    private var lastTick = 0.0
    private var movementStart: Double?
    private var pendingSelection: (Int, HintAction)?
    private var lastFlags: CGEventFlags = []
    private var screenObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private(set) var paused = false
    let hints = HintController()
    let scrolls = ScrollController()
    private static let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    init(postPointerEvents: Bool = true) {
        self.postPointerEvents = postPointerEvents
        configure(NavigationConfig())
        hints.status = { [weak self] in self?.onStatus($0) }
        hints.clicked = { [weak self] in self?.onClick() }
        hints.completed = { [weak self] in self?.pendingSelection = nil }
        hints.onSelection = { [weak self] id, action in self?.pendingSelection = (id, action); self?.flushSelection() }
        scrolls.status = { [weak self] in self?.onStatus($0) }
    }
    func configure(_ config: NavigationConfig) {
        cancelModes()
        self.config = config
        bindings = config.bindings.mapValues { NativeBinding.parse($0)! }
        hints.labelSize = config.hintLabelSize
    }
    func start() {
        stop()
        checkPermission(prompt: config.requestAccessibilityOnStart)
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !AXIsProcessTrusted() { self.stopMonitoring(); self.onPermission(false) }
            else if self.eventTap == nil, !self.paused { self.checkPermission() }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.cancelModes() }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.cancelModes() }
    }
    func checkPermission(prompt: Bool = false) {
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary)
        onPermission(trusted)
        guard trusted, !paused else { stopMonitoring(); return }
        guard eventTap == nil else { return }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: inputCallback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            onStatus("Keyboard hook unavailable. Check Accessibility permission."); return
        }
        eventTap = tap
        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        onStatus("Ready")
    }
    func setPaused(_ paused: Bool) {
        self.paused = paused
        if paused { stopMonitoring(); onStatus("Paused") } else { checkPermission() }
    }
    func cancelModes() {
        pendingSelection = nil
        hints.cancel(); scrolls.cancel()
        setActive(false)
        releasePointerButton()
    }
    private func stopMonitoring() {
        cancelModes()
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false); CFMachPortInvalidate(eventTap) }
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        eventTap = nil; eventTapSource = nil
        suppressedKeyUps.removeAll()
    }
    func stop() {
        permissionTimer?.invalidate(); permissionTimer = nil
        stopMonitoring()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }; screenObserver = nil
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }; workspaceObserver = nil
    }
    func setActive(_ active: Bool) {
        guard movement.active != active else { return }
        if !active { releasePointerButton(); clickKey = nil; clickModifier = nil }
        movement.activate(active)
        heldDirections.removeAll()
        if !active { stopMovement() }
    }
    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelModes()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard !paused else { return Unmanaged.passUnretained(event) }
        if type == .leftMouseDown || type == .rightMouseDown || type == .scrollWheel {
            let tag = event.getIntegerValueField(.eventSourceUserData)
            if ![hintMouseEventTag, freeMouseEventTag, scrollMouseEventTag].contains(tag) { cancelModes() }
            return Unmanaged.passUnretained(event)
        }
        let key = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        lastFlags = flags
        if type == .keyUp, suppressedKeyUps.remove(key) != nil {
            if let direction = heldDirections.removeValue(forKey: key) { movement.direction(direction, pressed: false); updateMovementTimer() }
            if clickKey == key { releasePointerButton(); clickKey = nil }
            flushSelection()
            return nil
        }
        if type == .keyDown, suppressedKeyUps.contains(key), !movement.active, !hints.capturing, !scrolls.capturing { return nil }
        if type == .flagsChanged {
            let activation = bindings["free_mode"]!
            if activation.handlesModifierEvent(keyCode: key) {
                let pressed = activation.isModifierPressed(flags: flags)
                // A second modifier while an overlay is open must not cancel that overlay.
                if !pressed { setActive(false) }
                else if !hints.capturing && !scrolls.capturing { setActive(true) }
            }
            if movement.active {
                movement.fast = speedPressed("fast_modifier", flags: flags)
                movement.precise = speedPressed("precision_modifier", flags: flags)
                for (action, button) in [("right_click", CGMouseButton.right), ("left_click", .left)] {
                    let binding = bindings[action]!
                    guard binding.handlesModifierEvent(keyCode: key) else { continue }
                    let pressed = binding.isModifierPressed(flags: flagsWithoutActivation(flags))
                    if pressed, pointerButtonDown == nil { clickModifier = action; pressPointerButton(button) }
                    else if !pressed, clickModifier == action { releasePointerButton(); clickModifier = nil }
                    return nil
                }
            }
            flushSelection()
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            for (action, mode) in [("hint_mode", 0), ("scroll_mode", 1), ("focus_mode", 2)] where bindings[action]!.matches(keyCode: key, flags: flags) {
                if suppressedKeyUps.insert(key).inserted {
                    let wasActive = mode == 1 ? scrolls.capturing : hints.capturing
                    cancelModes()
                    if !wasActive, postPointerEvents {
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !self.paused else { return }
                            if mode == 1 { self.scrolls.begin() } else { self.hints.begin(focusOnly: mode == 2) }
                        }
                    }
                }
                return nil
            }
        }
        if hints.capturing {
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { suppressedKeyUps.insert(key); return nil }
            let commands = [("hint_cancel", "ESCAPE"), ("hint_backspace", "BACKSPACE"), ("hint_next", "NEXT"), ("hint_previous", "PREVIOUS"), ("hint_click", "CLICK"), ("hint_focus", "FOCUS"), ("hint_right_click", "RIGHT_CLICK"), ("hint_command_click", "COMMAND_CLICK"), ("hint_size_up", "SIZE_UP"), ("hint_size_down", "SIZE_DOWN")]
            if let command = match(commands, key: key, flags: flags) {
                suppressedKeyUps.insert(key); hints.key(command); return nil
            }
            if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
                hints.cancel(); return Unmanaged.passUnretained(event)
            }
            suppressedKeyUps.insert(key)
            var characters = [UniChar](repeating: 0, count: 4), length = 0
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &characters)
            let text = String(utf16CodeUnits: characters, count: length).uppercased()
            if text.count == 1 { hints.key(text) }
            return nil
        }
        if scrolls.capturing {
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            let commands = [("scroll_cancel", "ESCAPE"), ("scroll_next", "NEXT"), ("scroll_previous", "PREVIOUS"), ("scroll_left", "LEFT"), ("scroll_down", "DOWN"), ("scroll_up", "UP"), ("scroll_right", "RIGHT"), ("scroll_half_down", "HALF_DOWN"), ("scroll_half_up", "HALF_UP"), ("scroll_top", "TOP"), ("scroll_bottom", "BOTTOM")]
            let command = match(commands, key: key, flags: flags) ?? match(Array(commands.dropFirst(3)), key: key, flags: flags.subtracting(.maskShift))
            if let command { suppressedKeyUps.insert(key); scrolls.key(command, dash: flags.contains(.maskShift)); return nil }
            if flags.intersection(Self.relevant).isEmpty, let digit = NativeBinding.keyCodes.first(where: { $0.value == key && "123456789".contains($0.key) })?.key {
                suppressedKeyUps.insert(key); scrolls.key(digit); return nil
            }
            scrolls.cancel(); return Unmanaged.passUnretained(event)
        }
        // Recover activation when the app starts with Super already held.
        if type == .keyDown, !movement.active, bindings["free_mode"]!.isModifierPressed(flags: flags) { setActive(true) }
        guard movement.active else { return Unmanaged.passUnretained(event) }
        let localFlags = flagsWithoutActivation(flags)
        if type == .keyDown, let action = match([("right_click", "RIGHT"), ("left_click", "LEFT")], key: key, flags: localFlags) {
            suppressedKeyUps.insert(key)
            if pointerButtonDown == nil { clickKey = key; pressPointerButton(action == "RIGHT" ? .right : .left) }
            return nil
        }
        if type == .keyDown, let value = match([("move_left", "left"), ("move_down", "down"), ("move_up", "up"), ("move_right", "right")], key: key, flags: localFlags, exact: false), let direction = Direction(rawValue: value) {
            suppressedKeyUps.insert(key); heldDirections[key] = direction
            movement.direction(direction, pressed: true)
            movement.fast = speedPressed("fast_modifier", flags: flags)
            movement.precise = speedPressed("precision_modifier", flags: flags)
            updateMovementTimer()
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
    private func match(_ actions: [(String, String)], key: CGKeyCode, flags: CGEventFlags, exact: Bool = true) -> String? {
        actions.first { bindings[$0.0]!.matches(keyCode: key, flags: flags, exactModifiers: exact) }?.1
    }
    private func flagsWithoutActivation(_ flags: CGEventFlags) -> CGEventFlags { flags.subtracting(bindings["free_mode"]!.activationModifierFlags) }
    private func speedPressed(_ action: String, flags: CGEventFlags) -> Bool {
        let binding = bindings[action]!
        if case .genericModifier = binding.trigger, !binding.activationModifierFlags.intersection(bindings["free_mode"]!.activationModifierFlags).isEmpty { return false }
        return binding.isModifierPressed(flags: flags)
    }
    private func flushSelection() {
        guard let selection = pendingSelection, suppressedKeyUps.isEmpty, lastFlags.intersection(Self.relevant).isEmpty else { return }
        pendingSelection = nil
        let generation = hints.generationID
        DispatchQueue.main.async { [weak self] in
            guard let self, self.hints.generationID == generation else { return }
            self.hints.activate(selection.0, action: selection.1)
        }
    }
    private func updateMovementTimer() {
        guard movement.active, movement.vector != .zero else { stopMovement(); return }
        guard moveTimer == nil, postPointerEvents else { return }
        lastTick = ProcessInfo.processInfo.systemUptime; movementStart = lastTick
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); moveTimer = timer
    }
    private func stopMovement() { moveTimer?.invalidate(); moveTimer = nil; movementStart = nil }
    private func tick() {
        guard movement.active, eventTap != nil else { stopMovement(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let delta = movement.displacement(heldSeconds: now - (movementStart ?? now), elapsedSeconds: now - lastTick, speed: config.pointerSpeed)
        lastTick = now
        moveCursor(dx: delta.x, dy: delta.y)
    }
    func moveCursor(dx: Double, dy: Double) {
        guard movement.active, dx.isFinite, dy.isFinite, let current = CGEvent(source: nil)?.location else { return }
        var destination = CGPoint(x: current.x + dx, y: current.y + dy)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        if !screens.isEmpty, !screens.contains(where: { $0.contains(destination) }) {
            destination = screens.map { rect in CGPoint(x: min(rect.maxX - 1, max(rect.minX, destination.x)), y: min(rect.maxY - 1, max(rect.minY, destination.y))) }.min { hypot($0.x - destination.x, $0.y - destination.y) < hypot($1.x - destination.x, $1.y - destination.y) }!
        }
        let type: CGEventType = pointerButtonDown == .left ? .leftMouseDragged : pointerButtonDown == .right ? .rightMouseDragged : .mouseMoved
        lastMovementEventType = type
        guard postPointerEvents else { return }
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: destination, mouseButton: pointerButtonDown ?? .left)
        event?.flags = []; event?.setIntegerValueField(.eventSourceUserData, value: freeMouseEventTag)
        event?.post(tap: .cghidEventTap)
    }
    func pressPointerButton(_ button: CGMouseButton) {
        guard movement.active, pointerButtonDown == nil else { return }
        pointerButtonDown = button; postButton(button, down: true)
    }
    func releasePointerButton() {
        guard let button = pointerButtonDown else { return }
        postButton(button, down: false); pointerButtonDown = nil
        if postPointerEvents { onClick() }
    }
    private func postButton(_ button: CGMouseButton, down: Bool) {
        guard postPointerEvents, let point = CGEvent(source: nil)?.location else { return }
        let type: CGEventType = button == .right ? (down ? .rightMouseDown : .rightMouseUp) : (down ? .leftMouseDown : .leftMouseUp)
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        event?.flags = []; event?.setIntegerValueField(.mouseEventClickState, value: 1)
        event?.setIntegerValueField(.eventSourceUserData, value: freeMouseEventTag)
        event?.post(tap: .cghidEventTap)
    }
    deinit { permissionTimer?.invalidate(); moveTimer?.invalidate() }
}
private func inputCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<InputController>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}
