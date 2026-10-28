// Generates the template menu-bar icon for mlh: the text "/␣" (slash, space) drawn in black
// on a transparent background, at 16x16 (1x) and 32x32 (2x), saved as TIFF.
//
// usage: swift scripts/make-icon.swift <output.tiff>
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.tiff>\n".data(using: .utf8)!)
    exit(2)
}
let outputURL = URL(fileURLWithPath: args[1])

func makeRep(scale: Int) -> NSBitmapImageRep {
    let points = 16
    let pixels = points * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: points, height: points)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: points, height: points).fill()

    let text = "/␣" as NSString
    var fontSize: CGFloat = 13
    var attrs: [NSAttributedString.Key: Any] = [:]
    var size = NSSize.zero
    // Shrink until it fits in the 16pt square with a little margin.
    repeat {
        attrs = [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                 .foregroundColor: NSColor.black]
        size = text.size(withAttributes: attrs)
        fontSize -= 0.5
    } while size.width > 15 && fontSize > 6
    let origin = NSPoint(x: (CGFloat(points) - size.width) / 2,
                         y: (CGFloat(points) - size.height) / 2)
    text.draw(at: origin, withAttributes: attrs)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: NSSize(width: 16, height: 16))
image.addRepresentation(makeRep(scale: 1))
image.addRepresentation(makeRep(scale: 2))
image.isTemplate = true

guard let tiff = image.tiffRepresentation(using: .lzw, factor: 0) else {
    FileHandle.standardError.write("failed to create TIFF\n".data(using: .utf8)!)
    exit(1)
}
do {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try tiff.write(to: outputURL)
    print("wrote \(outputURL.path)")
} catch {
    FileHandle.standardError.write("failed to write \(outputURL.path): \(error)\n".data(using: .utf8)!)
    exit(1)
}
