import AppKit
import ImageIO

struct RGBA: Hashable, Sendable, Codable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8 = 255

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

struct PaletteColor: Identifiable, Sendable {
    var color: RGBA
    var count: Int
    var id: RGBA { color }
}

enum ImageFit: String, CaseIterable, Sendable, Codable {
    case fit = "Ajustar", fill = "Rellenar", stretch = "Estirar"
}

struct PixelSettings: Equatable, Sendable, Codable {
    var width = 48
    var height = 48
    var colorCount = 16
    var fit = ImageFit.fit
    var smooth = true
    var dither = false
    var flatColors = true

    var isValid: Bool { (1...512).contains(width) && (1...512).contains(height) && (2...64).contains(colorCount) }
}

struct SourceImage: @unchecked Sendable {
    let image: CGImage
    let name: String
}

// Row-major color matrix. Empty cells have alpha 0; painted cells are opaque.
struct PixelResult: Sendable, Equatable {
    let width: Int
    let height: Int
    private(set) var grid: [[RGBA]]
    var pixels: [RGBA] { grid.flatMap { $0 } }
    var palette: [PaletteColor] {
        var counts: [RGBA: Int] = [:]
        for row in grid {
            for color in row where color.a > 0 { counts[color, default: 0] += 1 }
        }
        return counts.map { PaletteColor(color: $0.key, count: $0.value) }.sorted {
            $0.count == $1.count ? $0.color.hex < $1.color.hex : $0.count > $1.count
        }
    }

    init(width: Int, height: Int, pixels: [RGBA], palette: [PaletteColor] = []) {
        precondition((1...512).contains(width) && (1...512).contains(height) && pixels.count == width * height)
        self.width = width; self.height = height
        grid = (0..<height).map { row in Array(pixels[(row * width)..<((row + 1) * width)]) }
    }

    subscript(row: Int, column: Int) -> RGBA {
        get { grid[row][column] }
        set { grid[row][column] = newValue.a == 0 ? RGBA(r: 0, g: 0, b: 0, a: 0) : RGBA(r: newValue.r, g: newValue.g, b: newValue.b) }
    }

    func cgImage(scale: Int = 1) throws -> CGImage {
        guard (1...32).contains(scale), width * scale <= 8192, height * scale <= 8192 else {
            throw PixelError.invalidExport
        }
        let w = width * scale, h = height * scale
        var data = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let p = grid[y / scale][x / scale]
                let i = (y * w + x) * 4
                data[i] = p.r; data[i + 1] = p.g; data[i + 2] = p.b; data[i + 3] = p.a
            }
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw PixelError.renderFailed }
        return image
    }
}

enum PixelError: LocalizedError {
    case invalidImage, invalidSize, invalidExport, renderFailed, exportFailed
    var errorDescription: String? {
        switch self {
        case .invalidImage: "No se pudo abrir la imagen. Prueba con PNG, JPEG, HEIC, TIFF, GIF o WebP."
        case .invalidSize: "El ancho y el alto deben estar entre 1 y 512 cuadrados."
        case .invalidExport: "La exportación admite hasta 8192 píxeles por lado. Reduce la escala."
        case .renderFailed: "No se pudo procesar la imagen. Intenta con otra imagen o un lienzo más pequeño."
        case .exportFailed: "No se pudo guardar el archivo. Comprueba la ubicación de destino."
        }
    }
}

enum PixelEngine {
    static func load(url: URL) throws -> SourceImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw PixelError.invalidImage }
        return SourceImage(image: image, name: url.deletingPathExtension().lastPathComponent)
    }

    static func render(source: CGImage, settings: PixelSettings) throws -> PixelResult {
        guard settings.isValid else { throw PixelError.invalidSize }
        let w = settings.width, h = settings.height
        let samples = settings.flatColors ? 4 : 1
        let sampleWidth = w * samples, sampleHeight = h * samples
        var bytes = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: sampleWidth, height: sampleHeight,
                                          bitsPerComponent: 8, bytesPerRow: sampleWidth * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw PixelError.renderFailed }
            context.scaleBy(x: CGFloat(samples), y: CGFloat(samples))
            context.interpolationQuality = settings.flatColors ? .none : (settings.smooth ? .high : .none)
            let sx = Double(w) / Double(source.width), sy = Double(h) / Double(source.height)
            let factor = settings.fit == .fill ? max(sx, sy) : min(sx, sy)
            let dw = settings.fit == .stretch ? Double(w) : Double(source.width) * factor
            let dh = settings.fit == .stretch ? Double(h) : Double(source.height) * factor
            context.draw(source, in: CGRect(x: (Double(w) - dw) / 2, y: (Double(h) - dh) / 2, width: dw, height: dh))
        }
        try Task.checkCancellation()
        func read(_ i: Int) -> RGBA {
            let a = Int(bytes[i + 3])
            guard a > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
            return RGBA(r: UInt8(min(255, Int(bytes[i]) * 255 / a)),
                        g: UInt8(min(255, Int(bytes[i + 1]) * 255 / a)),
                        b: UInt8(min(255, Int(bytes[i + 2]) * 255 / a)), a: UInt8(a))
        }
        var pixels = [RGBA]()
        pixels.reserveCapacity(w * h)
        for row in 0..<h {
            try Task.checkCancellation()
            for col in 0..<w {
                if !settings.flatColors {
                    var color = read((row * w + col) * 4)
                    color.a = color.a >= 128 ? 255 : 0
                    if color.a == 0 { color = RGBA(r: 0, g: 0, b: 0, a: 0) }
                    pixels.append(color)
                    continue
                }
                // Choose the dominant color in each cell, rather than averaging edges into muddy colors.
                var counts: [UInt32: Int] = [:]
                var representatives: [UInt32: RGBA] = [:]
                var order: [UInt32] = []
                for dy in 0..<samples {
                    for dx in 0..<samples {
                        var p = read(((row * samples + dy) * sampleWidth + col * samples + dx) * 4)
                        p.a = p.a >= 128 ? 255 : 0
                        // Merge almost identical edge shades so they do not consume the flat-color palette.
                        func flatChannel(_ value: UInt8) -> UInt8 {
                            if value <= 12 { return 0 }
                            if value >= 243 { return 255 }
                            return UInt8((Int(value) + 4) / 8 * 8)
                        }
                        p.r = flatChannel(p.r); p.g = flatChannel(p.g); p.b = flatChannel(p.b)
                        let key: UInt32 = p.a == 0 ? 0x1000000 : UInt32(p.r >> 3) << 10 | UInt32(p.g >> 3) << 5 | UInt32(p.b >> 3)
                        if counts[key] == nil { order.append(key); representatives[key] = p }
                        counts[key, default: 0] += 1
                    }
                }
                let dominant = order.max { counts[$0]! < counts[$1]! }!
                pixels.append(representatives[dominant]!)
            }
        }
        let colors = quantize(pixels, limit: settings.colorCount)
        if !colors.isEmpty {
            var errors = [[Double]](repeating: [0, 0, 0], count: pixels.count)
            var cache: [RGBA: RGBA] = [:]
            for i in pixels.indices {
                if i % w == 0 { try Task.checkCancellation() }
                let original = pixels[i]
                guard original.a > 0 else { continue }
                let input = [Double(original.r), Double(original.g), Double(original.b)]
                let adjusted = zip(input, errors[i]).map { min(255, max(0, $0 + $1)) }
                let selected: RGBA
                if !settings.dither, let cached = cache[original] {
                    selected = cached
                } else {
                    selected = colors.min { distance($0, adjusted) < distance($1, adjusted) }!
                    if !settings.dither { cache[original] = selected }
                }
                pixels[i] = RGBA(r: selected.r, g: selected.g, b: selected.b, a: original.a)
                if settings.dither {
                    let error = zip(adjusted, [Double(selected.r), Double(selected.g), Double(selected.b)]).map(-)
                    let x = i % w, y = i / w
                    for (dx, dy, weight) in [(1, 0, 7.0/16), (-1, 1, 3.0/16), (0, 1, 5.0/16), (1, 1, 1.0/16)] {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0 && nx < w && ny < h {
                            for channel in 0..<3 { errors[ny * w + nx][channel] += error[channel] * weight }
                        }
                    }
                }
            }
        }
        var counts: [RGBA: Int] = [:]
        for pixel in pixels where pixel.a > 0 {
            counts[RGBA(r: pixel.r, g: pixel.g, b: pixel.b), default: 0] += 1
        }
        let entries: [PaletteColor] = counts.map { PaletteColor(color: $0.key, count: $0.value) }
        let palette = entries.sorted { (left: PaletteColor, right: PaletteColor) -> Bool in
            if left.count == right.count { return left.color.hex < right.color.hex }
            return left.count > right.count
        }
        return PixelResult(width: w, height: h, pixels: pixels, palette: palette)
    }

    static func reduce(_ result: PixelResult, limit: Int) -> PixelResult {
        let colors = quantize(result.pixels, limit: max(2, min(64, limit)))
        let mapped = result.pixels.map { p -> RGBA in
            guard p.a > 0 else { return p }
            return colors.min { distance($0, [Double(p.r), Double(p.g), Double(p.b)]) < distance($1, [Double(p.r), Double(p.g), Double(p.b)]) } ?? p
        }
        return PixelResult(width: result.width, height: result.height, pixels: mapped)
    }

    private static func distance(_ color: RGBA, _ value: [Double]) -> Double {
        let r = Double(color.r) - value[0], g = Double(color.g) - value[1], b = Double(color.b) - value[2]
        return r * r + g * g + b * b
    }

    // Weighted median cut: frequent colors contribute proportionally to each representative.
    private static func quantize(_ pixels: [RGBA], limit: Int) -> [RGBA] {
        var histogram: [RGBA: Int] = [:]
        for p in pixels where p.a > 0 { histogram[RGBA(r: p.r, g: p.g, b: p.b), default: 0] += 1 }
        if histogram.count <= limit { return histogram.keys.sorted { $0.hex < $1.hex } }
        typealias Entry = (color: RGBA, count: Int)
        func channels(_ p: RGBA) -> [Int] { [Int(p.r), Int(p.g), Int(p.b)] }
        func spread(_ box: [Entry]) -> (range: Int, channel: Int) {
            let ranges = (0..<3).map { c in
                let values = box.map { channels($0.color)[c] }
                return values.max()! - values.min()!
            }
            let channel = ranges.indices.max { ranges[$0] < ranges[$1] }!
            return (ranges[channel], channel)
        }
        var boxes: [[Entry]] = [histogram.map { (color: $0.key, count: $0.value) }]
        while boxes.count < limit {
            guard let index = boxes.indices.filter({ boxes[$0].count > 1 }).max(by: {
                spread(boxes[$0]).range < spread(boxes[$1]).range
            }) else { break }
            let channel = spread(boxes[index]).channel
            let sorted = boxes.remove(at: index).sorted {
                let a = channels($0.color)[channel], b = channels($1.color)[channel]
                return a == b ? $0.color.hex < $1.color.hex : a < b
            }
            let half = sorted.reduce(0) { $0 + $1.count } / 2
            var sum = 0, split = 1
            for i in 0..<(sorted.count - 1) {
                sum += sorted[i].count; split = i + 1
                if sum >= half { break }
            }
            boxes.append(Array(sorted[..<split])); boxes.append(Array(sorted[split...]))
        }
        return boxes.map { box in
            let total = box.reduce(0) { $0 + $1.count }
            let rgb = (0..<3).map { c in UInt8(box.reduce(0) { $0 + channels($1.color)[c] * $1.count } / total) }
            return RGBA(r: rgb[0], g: rgb[1], b: rgb[2])
        }
    }
}
