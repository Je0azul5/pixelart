import CoreGraphics
import CoreText
import Foundation

struct PatternOptions: Equatable, Sendable {
    var grid = true
    var coordinates = true

    var margin: Int { coordinates ? 32 : 12 }
}

enum PatternRenderer {
    static func size(_ result: PixelResult, cellSize: Int, options: PatternOptions) -> CGSize {
        CGSize(width: result.width * cellSize + options.margin * 2,
               height: result.height * cellSize + options.margin * 2)
    }

    static func image(_ result: PixelResult, cellSize: Int, options: PatternOptions) throws -> CGImage {
        guard (1...32).contains(cellSize) else { throw PixelError.invalidExport }
        let size = size(result, cellSize: cellSize, options: options)
        guard size.width <= 8192, size.height <= 8192 else { throw PixelError.invalidExport }
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PixelError.renderFailed }
        draw(result, in: context, cellSize: cellSize, options: options)
        guard let image = context.makeImage() else { throw PixelError.renderFailed }
        return image
    }

    // The same drawing code drives the preview, raster exports and vector PDF.
    static func draw(_ result: PixelResult, in context: CGContext, cellSize: Int, options: PatternOptions) {
        let size = size(result, cellSize: cellSize, options: options)
        let margin = CGFloat(options.margin), cell = CGFloat(cellSize)
        let width = CGFloat(result.width) * cell, height = CGFloat(result.height) * cell
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setShouldAntialias(false)
        for row in 0..<result.height {
            for col in 0..<result.width {
                let p = result.pixels[row * result.width + col]
                guard p.a > 0 else { continue }
                context.setFillColor(CGColor(srgbRed: CGFloat(p.r) / 255, green: CGFloat(p.g) / 255,
                                            blue: CGFloat(p.b) / 255, alpha: CGFloat(p.a) / 255))
                context.fill(CGRect(x: margin + CGFloat(col) * cell,
                                    y: margin + CGFloat(result.height - row - 1) * cell,
                                    width: cell, height: cell))
            }
        }
        if options.grid {
            context.setShouldAntialias(true)
            context.setStrokeColor(CGColor(gray: 0.1, alpha: 0.42))
            context.setLineWidth(max(0.35, cell / 25))
            for col in 0...result.width {
                let x = margin + CGFloat(col) * cell
                context.move(to: CGPoint(x: x, y: margin)); context.addLine(to: CGPoint(x: x, y: margin + height))
            }
            for row in 0...result.height {
                let y = margin + CGFloat(row) * cell
                context.move(to: CGPoint(x: margin, y: y)); context.addLine(to: CGPoint(x: margin + width, y: y))
            }
            context.strokePath()
            context.setStrokeColor(CGColor(gray: 0.1, alpha: 0.85))
            context.setLineWidth(max(0.8, cell / 15))
            context.stroke(CGRect(x: margin, y: margin, width: width, height: height))
        }
        if options.coordinates {
            context.setShouldAntialias(true)
            let font = CTFontCreateWithName("Menlo" as CFString, min(12, max(7, cell * 0.65)), nil)
            func label(_ number: Int, x: CGFloat, y: CGFloat) {
                let text = NSAttributedString(string: String(number), attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1)
                ])
                let line = CTLineCreateWithAttributedString(text)
                let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                context.textMatrix = .identity
                context.textPosition = CGPoint(x: x - bounds.width / 2, y: y - bounds.height / 2)
                CTLineDraw(line, context)
            }
            let step = cellSize < 8 ? 10 : (max(result.width, result.height) > 100 ? 5 : 2)
            for col in 1...result.width where col == 1 || col % step == 0 {
                label(col, x: margin + (CGFloat(col) - 0.5) * cell, y: margin + height + 16)
            }
            for row in 1...result.height where row == 1 || row % step == 0 {
                label(row, x: margin / 2, y: margin + height - (CGFloat(row) - 0.5) * cell)
            }
        }
    }
}
