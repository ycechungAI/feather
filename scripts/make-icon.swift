// Draws Feather's app icon and writes Support/Feather.icns.
// Usage: swift scripts/make-icon.swift   (needs only the Command Line Tools)
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024 // design on a 1024 grid

    // Rounded-square background (macOS icon grid: 824pt body inside 1024 with a soft shadow).
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.75, blue: 0.80, alpha: 1),
                        NSColor(srgbRed: 0.16, green: 0.36, blue: 0.86, alpha: 1)])!
        .draw(in: shape, angle: -90)

    // A white feather, drawn upright then rotated 40° around the icon's centre.
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: 512 * s, y: 512 * s)
    ctx.rotate(by: -40 * .pi / 180)
    ctx.translateBy(x: -512 * s, y: -512 * s)

    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
    let vane = NSBezierPath()
    vane.move(to: p(512, 860))
    vane.curve(to: p(372, 420), controlPoint1: p(400, 780), controlPoint2: p(340, 560))
    vane.line(to: p(420, 440))
    vane.curve(to: p(512, 260), controlPoint1: p(430, 360), controlPoint2: p(480, 300))
    vane.curve(to: p(604, 440), controlPoint1: p(544, 300), controlPoint2: p(594, 360))
    vane.line(to: p(652, 420))
    vane.curve(to: p(512, 860), controlPoint1: p(684, 560), controlPoint2: p(624, 780))
    vane.close()
    NSColor.white.withAlphaComponent(0.96).setFill()
    vane.fill()

    // Barb notches and the quill.
    NSColor(srgbRed: 0.16, green: 0.45, blue: 0.86, alpha: 0.55).setStroke()
    for (y, dx) in [(700.0, 70.0), (600, 95), (500, 95)] as [(CGFloat, CGFloat)] {
        for side in [-1.0, 1.0] as [CGFloat] {
            let barb = NSBezierPath()
            barb.lineWidth = 10 * s
            barb.lineCapStyle = .round
            barb.move(to: p(512, y - 30))
            barb.line(to: p(512 + side * dx, y + 20))
            barb.stroke()
        }
    }
    let quill = NSBezierPath()
    quill.lineWidth = 16 * s
    quill.lineCapStyle = .round
    quill.move(to: p(512, 820))
    quill.line(to: p(512, 160))
    NSColor(srgbRed: 0.10, green: 0.30, blue: 0.70, alpha: 0.7).setStroke()
    quill.stroke()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Feather.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    // 1024 px (512@2x) is skipped: it would double the app's size for no visible gain.
    for scale in [1, 2] where !(base == 512 && scale == 2) {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
let out = root.appendingPathComponent("Support/Feather.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
try? drawIcon(size: 512).representation(using: .png, properties: [:])!
    .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Feather-preview.png"))
print(task.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
