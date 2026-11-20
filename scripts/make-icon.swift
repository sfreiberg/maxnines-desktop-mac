// Draws the app icon, the same 9 as the web app's favicon.svg, in the macOS
// icon shape, and writes Resources/AppIcon.icns.
// Run with: swift scripts/make-icon.swift
import AppKit

let green = NSColor(srgbRed: 0x6f / 255, green: 0xdc / 255, blue: 0x8c / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x06 / 255, green: 0x20 / 255, blue: 0x0f / 255, alpha: 1)

/// One square PNG of `pixels` on a side. The shape fills 824 of every 1024
/// pixels, as Apple's icon grid has it, leaving room for its shadow.
func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    let unit = CGFloat(pixels) / 1024
    // Flip so the drawing reads top-down, like the SVG.
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: unit, y: -unit)

    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: 10)
    shadow.shadowBlurRadius = 20
    shadow.set()
    green.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // favicon.svg's 32-unit square, scaled into the tile.
    let scale = tile.width / 32
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: tile.minX + x * scale, y: tile.minY + y * scale)
    }
    ink.setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(
        origin: point(16 - 5, 12.7 - 5), size: NSSize(width: 10 * scale, height: 10 * scale)))
    ring.lineWidth = 4.2 * scale
    ring.stroke()
    let tail = NSBezierPath()
    tail.move(to: point(20.6, 14.7))
    tail.line(to: point(15, 23.9))
    tail.lineWidth = 4.2 * scale
    tail.lineCapStyle = .round
    tail.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try png(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { exit(1) }
print("Wrote Resources/AppIcon.icns")
