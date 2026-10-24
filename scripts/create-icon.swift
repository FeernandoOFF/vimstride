import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let backdrop = NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88), xRadius: p * 0.20, yRadius: p * 0.20)
        NSGradient(starting: NSColor(calibratedRed: 0.18, green: 0.47, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0.20, green: 0.23, blue: 0.68, alpha: 1))!.draw(in: backdrop, angle: -70)
        let pointer = NSBezierPath()
        pointer.move(to: NSPoint(x: p * 0.32, y: p * 0.76))
        for (x,y) in [(0.32,0.25),(0.45,0.38),(0.56,0.19),(0.66,0.25),(0.55,0.43),(0.75,0.43)] { pointer.line(to: NSPoint(x: p * x, y: p * y)) }
        pointer.close(); NSColor.white.setFill(); pointer.fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
