import AppKit

struct OverlayHint {
    let bounds: CGRect // Quartz global coordinates (top-left origin).
    let label: String
    var focused = false
}

private final class HintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HintCanvas: NSView {
    var hints: [OverlayHint] = []
    var prefix = ""
    var fontSize: CGFloat = 13
    var quartzFrame = CGRect.zero
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        var occupied: [CGRect] = []
        for hint in hints {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let text = NSMutableAttributedString(string: hint.label, attributes: attributes)
            if !prefix.isEmpty {
                text.addAttribute(.foregroundColor, value: NSColor.systemBrown, range: NSRange(location: 0, length: min(prefix.count, hint.label.count)))
            }
            let size = text.size()
            let width = size.width + 10
            let height = size.height + 5
            let anchorX = hint.bounds.minX - quartzFrame.minX
            let anchorY = hint.bounds.minY - quartzFrame.minY
            var box = CGRect.zero
            // A small collision pass keeps adjacent/nested controls readable.
            for offset in 0..<8 {
                let x = min(max(2, anchorX), max(2, bounds.width - width - 2))
                let y = min(max(2, anchorY + CGFloat(offset) * (height + 2)), max(2, bounds.height - height - 2))
                box = CGRect(x: x, y: y, width: width, height: height)
                if !occupied.contains(where: { $0.insetBy(dx: -1, dy: -1).intersects(box) }) { break }
            }
            occupied.append(box)
            if box.minY > anchorY + 2 {
                let leader = NSBezierPath()
                leader.move(to: CGPoint(x: anchorX + 3, y: anchorY + 3))
                leader.line(to: CGPoint(x: box.minX + 3, y: box.minY + 3))
                NSColor.systemOrange.setStroke()
                leader.stroke()
            }
            if hint.focused {
                let focusBounds = hint.bounds.offsetBy(dx: -quartzFrame.minX, dy: -quartzFrame.minY).insetBy(dx: -2, dy: -2)
                NSColor.systemGreen.setStroke()
                let outline = NSBezierPath(roundedRect: focusBounds, xRadius: 4, yRadius: 4)
                outline.lineWidth = 2; outline.stroke()
            }
            let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            NSColor(calibratedRed: 1, green: 0.87, blue: 0.30, alpha: 0.98).setFill()
            path.fill()
            NSColor(calibratedWhite: 0.15, alpha: 0.85).setStroke()
            path.lineWidth = 1
            path.stroke()
            text.draw(at: CGPoint(x: box.minX + 5, y: box.minY + 2))
        }
    }
}

final class HintOverlay {
    private var panels: [HintPanel] = []

    func show(_ hints: [OverlayHint], prefix: String, fontSize: CGFloat) {
        hide()
        guard let primaryScreen = NSScreen.screens.first else { return }
        let originY = primaryScreen.frame.maxY
        for screen in NSScreen.screens {
            let quartzFrame = CGRect(x: screen.frame.minX, y: originY - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
            let visible = hints.filter { quartzFrame.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }
            guard !visible.isEmpty else { continue }
            let panel = HintPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .clear
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let canvas = HintCanvas(frame: CGRect(origin: .zero, size: screen.frame.size))
            canvas.quartzFrame = quartzFrame
            canvas.hints = visible
            canvas.prefix = prefix
            canvas.fontSize = fontSize
            panel.contentView = canvas
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
    }
}

struct OverlayScrollRegion {
    let id: Int
    let bounds: CGRect // Quartz global coordinates (top-left origin).
    let number: Int
    let count: Int
}

final class ScrollCanvas: NSView {
    var regions: [OverlayScrollRegion] = []
    var selectedID = -1
    var quartzFrame = CGRect.zero
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for region in regions {
            let rect = region.bounds.offsetBy(dx: -quartzFrame.minX, dy: -quartzFrame.minY).insetBy(dx: 2, dy: 2)
            let selected = region.id == selectedID
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            if selected {
                NSColor.systemBlue.withAlphaComponent(0.08).setFill()
                path.fill()
                NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
                path.lineWidth = 3
            } else {
                NSColor.systemGray.withAlphaComponent(0.48).setStroke()
                path.lineWidth = 1.5
            }
            path.stroke()

            let label = selected ? "SCROLL \(region.number)/\(region.count)" : "\(region.number)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: selected ? 12 : 11, weight: .bold),
                .foregroundColor: selected ? NSColor.white : NSColor.labelColor,
            ]
            let text = NSAttributedString(string: label, attributes: attributes)
            let size = text.size()
            let box = CGRect(
                x: min(max(4, rect.minX + 8), max(4, bounds.width - size.width - 18)),
                y: min(max(4, rect.minY + 8), max(4, bounds.height - size.height - 12)),
                width: size.width + 10,
                height: size.height + 5
            )
            let badge = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            (selected ? NSColor.systemBlue : NSColor.windowBackgroundColor.withAlphaComponent(0.9)).setFill()
            badge.fill()
            (selected ? NSColor.systemBlue : NSColor.systemGray.withAlphaComponent(0.7)).setStroke()
            badge.stroke()
            text.draw(at: CGPoint(x: box.minX + 5, y: box.minY + 2))
        }
    }
}

final class ScrollOverlay {
    private var panels: [HintPanel] = []

    func show(_ regions: [OverlayScrollRegion], selectedID: Int) {
        hide()
        guard let primaryScreen = NSScreen.screens.first else { return }
        let originY = primaryScreen.frame.maxY
        for screen in NSScreen.screens {
            let quartzFrame = CGRect(
                x: screen.frame.minX,
                y: originY - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            let visible = regions.filter { $0.bounds.intersects(quartzFrame) }
            guard !visible.isEmpty else { continue }
            let panel = HintPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let canvas = ScrollCanvas(frame: CGRect(origin: .zero, size: screen.frame.size))
            canvas.quartzFrame = quartzFrame
            canvas.regions = visible
            canvas.selectedID = selectedID
            panel.contentView = canvas
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
    }
}
