import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("JeXelart.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                     ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                     ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: size * 4, bitsPerPixel: 32),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("No se pudo crear el contexto del icono")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let s = CGFloat(size)
    NSColor(srgbRed: 0.065, green: 0.035, blue: 0.115, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.05, y: s * 0.05, width: s * 0.9, height: s * 0.9), xRadius: s * 0.2, yRadius: s * 0.2).fill()
    let unit = s * 0.145, origin = s * 0.21
    for index in [0, 3, 5, 6, 9, 10, 12, 15] {
        NSColor(srgbRed: 0.70, green: 0.43, blue: 1, alpha: 1).setFill()
        NSRect(x: origin + CGFloat(index % 4) * unit, y: s - origin - CGFloat(index / 4 + 1) * unit,
               width: unit * 0.9, height: unit * 0.9).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("No se pudo generar el icono")
    }
    try png.write(to: directory.appendingPathComponent("\(name).png"))
}
