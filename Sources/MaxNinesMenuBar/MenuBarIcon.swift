import AppKit
import MaxNinesKit

/// What the menu bar icon says: the worst thing happening.
enum IconState: Equatable {
    /// Nothing firing: plain, like the icons around it.
    case quiet
    /// Warnings only: an amber square and how many.
    case warnings(Int)
    /// Something critical: a red dot and how many alerts are firing in all.
    case critical(Int)
    /// The server can't be asked, or hasn't answered yet: dimmed and dashed, so
    /// quiet isn't mistaken for fine.
    case unknown

    init(overview: Overview?, problem: String?) {
        guard let overview, problem == nil else {
            self = .unknown
            return
        }
        switch overview.worst {
        case .critical: self = .critical(overview.firing.count)
        case .warning: self = .warnings(overview.firing.count)
        case nil: self = .quiet
        }
    }
}

/// Draws the icon. Its colours are worked out each time it's drawn, so it suits
/// a light or dark menu bar, and it isn't a template image, as macOS would take
/// the colour out of one.
func menuBarImage(_ state: IconState) -> NSImage {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    let text: String?
    switch state {
    case .quiet: text = nil
    case .warnings(let count), .critical(let count): text = "\(count)"
    case .unknown: text = "?"
    }
    let textWidth = text.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) } ?? 0
    let markWidth: CGFloat = {
        switch state {
        case .warnings, .critical: 8 + 4
        default: 0
        }
    }()
    let width = 16 + (text == nil ? 0 : 4 + markWidth + textWidth)
    let size = NSSize(width: width, height: 18)

    let image = NSImage(size: size, flipped: true) { _ in
        let dimmed = state == .unknown
        let ink = dimmed ? NSColor.secondaryLabelColor : NSColor.labelColor
        drawNine(in: NSRect(x: 0, y: 1, width: 16, height: 16), colour: ink, dashed: dimmed)

        var x: CGFloat = 20
        let colour: NSColor
        switch state {
        case .critical:
            colour = .systemRed
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: 5, width: 8, height: 8)).fill()
            x += 12
        case .warnings:
            colour = .systemOrange
            NSColor.systemOrange.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 5, width: 8, height: 8), xRadius: 2, yRadius: 2).fill()
            x += 12
        case .unknown:
            colour = .secondaryLabelColor
        case .quiet:
            colour = ink
        }
        if let text {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
            let height = (text as NSString).size(withAttributes: attributes).height
            (text as NSString).draw(at: NSPoint(x: x, y: (18 - height) / 2), withAttributes: attributes)
        }
        return true
    }
    image.isTemplate = false
    return image
}

/// MaxNines' mark: a 9 in a rounded square, drawn in a 16 point box.
private func drawNine(in box: NSRect, colour: NSColor, dashed: Bool) {
    let scale = box.width / 16
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: box.minX + x * scale, y: box.minY + y * scale)
    }
    colour.setStroke()

    let square = NSBezierPath(
        roundedRect: NSRect(origin: point(1, 1), size: NSSize(width: 14 * scale, height: 14 * scale)),
        xRadius: 4 * scale, yRadius: 4 * scale)
    square.lineWidth = 1.4 * scale
    if dashed {
        square.setLineDash([2.4 * scale, 2 * scale], count: 2, phase: 0)
    }
    square.stroke()

    let nine = NSBezierPath()
    nine.lineWidth = 1.4 * scale
    nine.lineCapStyle = .round
    nine.appendOval(in: NSRect(origin: point(5.6, 4.2), size: NSSize(width: 4.8 * scale, height: 4.8 * scale)))
    nine.move(to: point(10.4, 6.6))
    nine.line(to: point(10.4, 8.8))
    nine.curve(to: point(7.5, 12), controlPoint1: point(10.4, 10.6), controlPoint2: point(9.3, 11.8))
    nine.stroke()
}
