// Retina-Hintergrund für das 700 × 440 große Finder-Fenster.
import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Aufruf: swift make-dmg-background.swift <dateipfad-ohne-endung>\n", stderr)
    exit(2)
}
let output = CommandLine.arguments[1]
let width: CGFloat = 700
let height: CGFloat = 440
func render(scale: CGFloat) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale),
        pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
    let base = NSGradient(colors: [
        NSColor(red: 0.21, green: 0.22, blue: 0.28, alpha: 1),
        NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)
    ])!
    base.draw(in: CGRect(x: 0, y: 0, width: width, height: height), angle: -75)
    let bloom = NSGradient(colors: [
        NSColor(red: 0.55, green: 0.49, blue: 1.0, alpha: 0.2),
        NSColor(red: 0.55, green: 0.49, blue: 1.0, alpha: 0)
    ])!
    bloom.draw(fromCenter: CGPoint(x: 530, y: 75), radius: 0,
               toCenter: CGPoint(x: 530, y: 75), radius: 330, options: [])

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    func text(_ value: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1) {
        NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(white: 1, alpha: alpha),
            .paragraphStyle: paragraph
        ]).draw(in: CGRect(x: 35, y: y, width: width - 70, height: size + 14))
    }
    text("Mischpult", y: 348, size: 34, weight: .bold)
    text("Jede App in ihrer eigenen Lautstärke.", y: 319, size: 15, weight: .medium, alpha: 0.65)

    // Die Icons werden von Finder darüber platziert.
    for centerX: CGFloat in [180, 520] {
        let platform = NSBezierPath(roundedRect: CGRect(x: centerX - 83, y: 147, width: 166, height: 158),
                                    xRadius: 27, yRadius: 27)
        NSColor(white: 1, alpha: 0.035).setFill()
        platform.fill()
        NSColor(white: 1, alpha: 0.065).setStroke()
        platform.lineWidth = 1
        platform.stroke()
    }
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 284, y: 230))
    arrow.line(to: CGPoint(x: 409, y: 230))
    arrow.move(to: CGPoint(x: 393, y: 246))
    arrow.line(to: CGPoint(x: 410, y: 230))
    arrow.line(to: CGPoint(x: 393, y: 214))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(red: 0.70, green: 0.66, blue: 1.0, alpha: 0.9).setStroke()
    arrow.stroke()

    text("Zum Installieren nach Programme ziehen", y: 62, size: 16, weight: .semibold)
    text("macOS 14.2 oder neuer", y: 36, size: 12, weight: .regular, alpha: 0.45)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
try render(scale: 1).write(to: URL(fileURLWithPath: output + ".png"))
try render(scale: 2).write(to: URL(fileURLWithPath: output + "@2x.png"))
