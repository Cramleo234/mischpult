// App-Icon aus eigenem Vektor-Artwork; Aufruf: swift make-icon.swift <iconset> [preview.png]
import AppKit

guard CommandLine.arguments.count >= 2 else {
    fputs("Aufruf: swift make-icon.swift <iconset> [preview.png]\n", stderr)
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)!
}
func draw(_ context: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 184, cornerHeight: 184, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 25, color: color(0x000000, alpha: 0.32))
    context.addPath(shape)
    context.setFillColor(color(0x15171F))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.drawLinearGradient(gradient([color(0x383C4A), color(0x12141B)]),
        start: CGPoint(x: 300, y: 924), end: CGPoint(x: 760, y: 100),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.drawRadialGradient(gradient([color(0x8C7CFF, alpha: 0.24), color(0x8C7CFF, alpha: 0)]),
        startCenter: CGPoint(x: 720, y: 190), startRadius: 0,
        endCenter: CGPoint(x: 720, y: 190), endRadius: 650, options: [])
    context.drawLinearGradient(gradient([color(0xFFFFFF, alpha: 0.06), color(0xFFFFFF, alpha: 0)]),
        start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 512), options: [])

    // Drei Schieberegler eines Mischpults auf unterschiedlicher Höhe.
    let columns: [(x: CGFloat, knob: CGFloat)] = [(352, 600), (512, 420), (672, 690)]
    for column in columns {
        let track = CGPath(roundedRect: CGRect(x: column.x - 13, y: 250, width: 26, height: 524),
                           cornerWidth: 13, cornerHeight: 13, transform: nil)
        context.addPath(track)
        context.setFillColor(color(0x000000, alpha: 0.38))
        context.fillPath()
        // Leuchtender Pegel unterhalb des Reglers.
        context.saveGState()
        context.addPath(CGPath(roundedRect: CGRect(x: column.x - 9, y: 254, width: 18, height: column.knob - 254),
                               cornerWidth: 9, cornerHeight: 9, transform: nil))
        context.clip()
        context.drawLinearGradient(gradient([color(0x6FD3FF), color(0xA48BFF)]),
            start: CGPoint(x: 0, y: 254), end: CGPoint(x: 0, y: 760), options: [])
        context.restoreGState()
    }
    for column in columns {
        let knob = CGRect(x: column.x - 74, y: column.knob - 34, width: 148, height: 68)
        let path = CGPath(roundedRect: knob, cornerWidth: 26, cornerHeight: 26, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8), blur: 26, color: color(0x000000, alpha: 0.5))
        context.addPath(path)
        context.setFillColor(color(0xF2F3F8))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(gradient([color(0xFFFFFF), color(0xC9CCDA)]),
            start: CGPoint(x: 0, y: knob.maxY), end: CGPoint(x: 0, y: knob.minY), options: [])
        context.restoreGState()
        context.setFillColor(color(0x5B5F73, alpha: 0.55))
        context.fill(CGRect(x: column.x - 44, y: column.knob - 3, width: 88, height: 6))
    }
    context.restoreGState()

    context.addPath(shape)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.13))
    context.setLineWidth(2)
    context.strokePath()
}
func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.interpolationQuality = .high
    draw(context)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
if CommandLine.arguments.count >= 3 {
    try render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
