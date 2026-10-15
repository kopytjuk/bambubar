import AppKit

/// Bamboo ("Bambu") glyph: three segmented stalks, plus leaves when drawn large.
/// Shared by the menu bar icon and the app icon generator.
func drawBamboo(in rect: CGRect, color: NSColor) {
    color.setFill()
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
    func stalk(x: CGFloat, width: CGFloat, segments: Int, height: CGFloat) {
        let gap = rect.height * 0.035
        let seg = (height * rect.height - gap * CGFloat(segments - 1)) / CGFloat(segments)
        for i in 0..<segments {
            let r = CGRect(x: rect.minX + x * rect.width, y: rect.minY + CGFloat(i) * (seg + gap),
                           width: width * rect.width, height: seg)
            NSBezierPath(roundedRect: r, xRadius: r.width * 0.2, yRadius: r.width * 0.2).fill()
        }
    }
    func leaf(from a: CGPoint, to b: CGPoint, width: CGFloat) {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x, dy = b.y - a.y, len = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let n = CGPoint(x: -dy / len * width * rect.width, y: dx / len * width * rect.width)
        let p = NSBezierPath()
        p.move(to: a)
        p.curve(to: b, controlPoint1: CGPoint(x: mid.x + n.x, y: mid.y + n.y),
                controlPoint2: CGPoint(x: mid.x + n.x, y: mid.y + n.y))
        p.curve(to: a, controlPoint1: CGPoint(x: mid.x - n.x, y: mid.y - n.y),
                controlPoint2: CGPoint(x: mid.x - n.x, y: mid.y - n.y))
        p.fill()
    }
    stalk(x: 0.16, width: 0.18, segments: 3, height: 0.84)
    stalk(x: 0.41, width: 0.18, segments: 3, height: 0.68)
    stalk(x: 0.66, width: 0.18, segments: 2, height: 0.50)
    if rect.width > 40 {
        leaf(from: pt(0.30, 0.76), to: pt(0.60, 0.98), width: 0.07)
        leaf(from: pt(0.30, 0.84), to: pt(0.02, 0.92), width: 0.06)
        leaf(from: pt(0.55, 0.62), to: pt(0.92, 0.80), width: 0.07)
    }
}

func bambooMenuBarImage() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
        drawBamboo(in: rect.insetBy(dx: 1, dy: 1), color: .black)
        return true
    }
    img.isTemplate = true
    return img
}
