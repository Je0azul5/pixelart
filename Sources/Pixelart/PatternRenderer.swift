import CoreGraphics
import CoreText
import Foundation

struct PatternOptions: Equatable, Sendable, Codable {
    var background = RGBA(r: 255, g: 255, b: 255)
    var grid = true
    var coordinates = true
    var symbolsEnabled = false
    var symbolAssignments: [RGBA: String] = [:]
    var hiddenSymbolColors: Set<RGBA> = []

    var margin: Int { coordinates ? 32 : 12 }

    static let symbols = ["×", "+", "○", "□", "★", "♥", "◇", "△", "●", "■", "◆", "▲"]
        + Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").map(String.init)
        + ["☆", "♡", "▽", "◁", "▷", "⊕", "⊗", "⊙", "⊞", "⊠", "≡", "=", "%", "#", "&", "?"]

    func resolvedSymbols(for palette: [PaletteColor]) -> [RGBA: String] {
        var assignments: [RGBA: String] = [:]
        var used: Set<String> = []
        for entry in palette {
            if let symbol = symbolAssignments[entry.color], Self.symbols.contains(symbol), !used.contains(symbol) {
                assignments[entry.color] = symbol
                used.insert(symbol)
            }
        }
        for entry in palette where assignments[entry.color] == nil {
            if let symbol = Self.symbols.first(where: { !used.contains($0) }) {
                assignments[entry.color] = symbol
                used.insert(symbol)
            }
        }
        return assignments
    }

    static func usesLightInk(for color: RGBA) -> Bool {
        func linear(_ value: UInt8) -> Double {
            let channel = (Double(value) / 255) * (Double(color.a) / 255) + 1 - Double(color.a) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b) < 0.179
    }
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
        context.setFillColor(CGColor(srgbRed: CGFloat(options.background.r) / 255, green: CGFloat(options.background.g) / 255, blue: CGFloat(options.background.b) / 255, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setShouldAntialias(false)
        context.setShouldSmoothFonts(false)
        let clip = context.boundingBoxOfClipPath.intersection(CGRect(origin: .zero, size: size))
        guard !clip.isNull else { return }
        let expanded = clip.insetBy(dx: -1, dy: -1)
        let firstColumn = max(0, min(result.width, Int(floor((expanded.minX - margin) / cell))))
        let endColumn = max(firstColumn, min(result.width, Int(ceil((expanded.maxX - margin) / cell))))
        let firstBottomRow = max(0, min(result.height, Int(floor((expanded.minY - margin) / cell))))
        let endBottomRow = max(firstBottomRow, min(result.height, Int(ceil((expanded.maxY - margin) / cell))))
        let firstRow = result.height - endBottomRow, endRow = result.height - firstBottomRow
        var colorCache: [RGBA: CGColor] = [:]
        for row in firstRow..<endRow {
            for col in firstColumn..<endColumn {
                let p = result[row, col]
                guard p.a > 0 else { continue }
                let fill: CGColor
                if let cached = colorCache[p] { fill = cached }
                else {
                    fill = CGColor(srgbRed: CGFloat(p.r) / 255, green: CGFloat(p.g) / 255,
                                   blue: CGFloat(p.b) / 255, alpha: CGFloat(p.a) / 255)
                    colorCache[p] = fill
                }
                context.setFillColor(fill)
                context.fill(CGRect(x: margin + CGFloat(col) * cell,
                                    y: margin + CGFloat(result.height - row - 1) * cell,
                                    width: cell, height: cell))
            }
        }
        if options.symbolsEnabled {
            context.setShouldAntialias(false)
            let symbols = options.resolvedSymbols(for: result.palette)
            let font = CTFontCreateWithName("Menlo" as CFString, cell * 0.72, nil)
            var lines: [String: CTLine] = [:]
            for symbol in Set(symbols.values) {
                // Text presentation keeps hearts and stars monochrome rather than turning into emoji.
                let text = NSAttributedString(string: symbol + "\u{FE0E}", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
                ])
                lines[symbol] = CTLineCreateWithAttributedString(text)
            }
            var boundsCache: [String: CGRect] = [:]
            let lightInk = Set(result.palette.filter { PatternOptions.usesLightInk(for: $0.color) }.map(\.color))
            for row in firstRow..<endRow {
                for col in firstColumn..<endColumn {
                    let pixel = result[row, col]
                    guard pixel.a > 0 else { continue }
                    let color = RGBA(r: pixel.r, g: pixel.g, b: pixel.b)
                    guard !options.hiddenSymbolColors.contains(color), let symbol = symbols[color], let line = lines[symbol] else { continue }
                    let bounds: CGRect
                    if let cached = boundsCache[symbol] { bounds = cached }
                    else { bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds); boundsCache[symbol] = bounds }
                    context.saveGState()
                    let rect = CGRect(x: margin + CGFloat(col) * cell, y: margin + CGFloat(result.height - row - 1) * cell,
                                      width: cell, height: cell)
                    context.clip(to: rect.insetBy(dx: cell * 0.1, dy: cell * 0.1))
                    context.setFillColor(CGColor(gray: lightInk.contains(color) ? 1 : 0, alpha: 1))
                    context.textMatrix = .identity
                    context.textPosition = CGPoint(x: rect.midX - bounds.midX, y: rect.midY - bounds.midY)
                    CTLineDraw(line, context)
                    context.restoreGState()
                }
            }
        }
        if options.grid {
            context.setShouldAntialias(false)
            context.setStrokeColor(CGColor(srgbRed: 0.25, green: 0.25, blue: 0.25, alpha: 1))
            context.setLineWidth(1)
            for col in firstColumn...endColumn {
                let x = margin + CGFloat(col) * cell + 0.5
                context.move(to: CGPoint(x: x, y: margin)); context.addLine(to: CGPoint(x: x, y: margin + height))
            }
            for row in firstBottomRow...endBottomRow {
                let y = margin + CGFloat(row) * cell + 0.5
                context.move(to: CGPoint(x: margin, y: y)); context.addLine(to: CGPoint(x: margin + width, y: y))
            }
            context.strokePath()

        }
        if options.coordinates {
            context.setShouldAntialias(false)
            let font = CTFontCreateWithName("Menlo" as CFString, min(12, max(7, cell * 0.65)), nil)
            func label(_ number: Int, x: CGFloat, y: CGFloat) {
                guard CGRect(x: x - 16, y: y - 8, width: 32, height: 16).intersects(clip) else { return }
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
            let step = max(1, Int(ceil(24 / cell)))
            for col in 1...result.width where col == 1 || col % step == 0 {
                label(col, x: margin + (CGFloat(col) - 0.5) * cell, y: margin + height + 16)
            }
            for row in 1...result.height where row == 1 || row % step == 0 {
                label(row, x: margin / 2, y: margin + height - (CGFloat(row) - 0.5) * cell)
            }
        }
    }
}
