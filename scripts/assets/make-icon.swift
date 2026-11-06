// Draws the MacIsle app icon (original artwork) at every size macOS needs.
// usage: swift make-icon.swift <AppIcon.appiconset dir>
import AppKit

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body with soft shadow.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let r = body.width * 0.225
    let shape = NSBezierPath(roundedRect: body, xRadius: r, yRadius: r)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); shape.fill()
    ctx.restoreGState()

    // Background: dusk gradient (a "screen" with a horizon glow).
    ctx.saveGState()
    shape.addClip()
    let bg = NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.20, alpha: 1),
                                 NSColor(calibratedRed: 0.20, green: 0.17, blue: 0.38, alpha: 1),
                                 NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.40, alpha: 1)],
                         atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
    bg.draw(in: body, angle: -90)
    // Menu-bar band
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSRect(x: body.minX, y: body.maxY - body.height * 0.17, width: body.width, height: body.height * 0.17).fill()

    // The island: a floating black capsule just below the top edge.
    let iw = body.width * 0.50, ih = body.height * 0.13
    let island = CGRect(x: body.midX - iw / 2, y: body.maxY - body.height * 0.035 - ih, width: iw, height: ih)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.035, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: island, xRadius: ih / 2, yRadius: ih / 2).fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Live activity: a glowing dot (left) and a waveform (right).
    let dot = ih * 0.46
    let dotRect = CGRect(x: island.minX + ih * 0.32, y: island.midY - dot / 2, width: dot, height: dot)
    NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: dotRect).fill()
    let barW = ih * 0.11, gap = ih * 0.08
    let heights: [CGFloat] = [0.34, 0.62, 0.46, 0.72]
    var x = island.maxX - ih * 0.36 - CGFloat(heights.count) * (barW + gap) + gap
    NSColor(calibratedRed: 0.55, green: 0.85, blue: 1.0, alpha: 1).setFill()
    for hgt in heights {
        let bh = ih * hgt
        NSBezierPath(roundedRect: CGRect(x: x, y: island.midY - bh / 2, width: barW, height: bh), xRadius: barW / 2, yRadius: barW / 2).fill()
        x += barW + gap
    }
    // Hairline sheen on the body edge.
    ctx.restoreGState()
    NSColor.white.withAlphaComponent(0.12).setStroke()
    shape.lineWidth = max(1, s / 512)
    shape.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
var images: [[String: String]] = []
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(pt)x\(pt)@\(scale)x.png"
    try! draw(pt * scale).write(to: dir.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(pt)x\(pt)"])
}
let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: dir.appendingPathComponent("Contents.json"))
print("icons written")
