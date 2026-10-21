import AppKit
import ImageIO

struct RGBA: Hashable, Sendable, Codable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8 = 255

    var sortKey: UInt32 { UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }
    var vector: SIMD3<Double> { SIMD3(Double(r), Double(g), Double(b)) }

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
    private var colorCounts: [RGBA: Int]
    var palette: [PaletteColor] {
        colorCounts.map { PaletteColor(color: $0.key, count: $0.value) }.sorted {
            $0.count == $1.count ? $0.color.sortKey < $1.color.sortKey : $0.count > $1.count
        }
    }

    init(width: Int, height: Int, pixels: [RGBA], palette: [PaletteColor] = []) {
        precondition((1...512).contains(width) && (1...512).contains(height) && pixels.count == width * height)
        self.width = width; self.height = height
        grid = (0..<height).map { row in Array(pixels[(row * width)..<((row + 1) * width)]) }
        colorCounts = [:]
        for color in pixels where color.a > 0 { colorCounts[color, default: 0] += 1 }
    }

    subscript(row: Int, column: Int) -> RGBA {
        get { grid[row][column] }
        set {
            let color = newValue.a == 0 ? RGBA(r: 0, g: 0, b: 0, a: 0) : RGBA(r: newValue.r, g: newValue.g, b: newValue.b)
            let old = grid[row][column]
            guard old != color else { return }
            grid[row][column] = color
            if old.a > 0 {
                if colorCounts[old] == 1 { colorCounts.removeValue(forKey: old) }
                else { colorCounts[old, default: 0] -= 1 }
            }
            if color.a > 0 { colorCounts[color, default: 0] += 1 }
        }
    }

    func cgImage(scale: Int = 1) throws -> CGImage {
        guard (1...32).contains(scale), width * scale <= 8192, height * scale <= 8192 else {
            throw PixelError.invalidExport
        }
        let w = width * scale, h = height * scale
        guard let data = CFDataCreateMutable(nil, w * h * 4) else { throw PixelError.renderFailed }
        CFDataSetLength(data, w * h * 4)
        let bytes = CFDataGetMutableBytePtr(data)!
        for row in 0..<height {
            let start = bytes.advanced(by: row * scale * w * 4)
            for column in 0..<width {
                let p = grid[row][column]
                for dx in 0..<scale {
                    let i = (column * scale + dx) * 4
                    start[i] = p.r; start[i + 1] = p.g; start[i + 2] = p.b; start[i + 3] = p.a
                }
            }
            for dy in 1..<scale { memcpy(start.advanced(by: dy * w * 4), start, w * 4) }
        }
        guard let provider = CGDataProvider(data: data),
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
        var sampleKeys = [UInt32](repeating: 0, count: 16)
        var sampleCounts = [Int](repeating: 0, count: 16)
        var representatives = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0), count: 16)
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
                var used = 0
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
                        if let index = (0..<used).first(where: { sampleKeys[$0] == key }) {
                            sampleCounts[index] += 1
                        } else {
                            sampleKeys[used] = key; sampleCounts[used] = 1; representatives[used] = p
                            used += 1
                        }
                    }
                }
                let dominant = (0..<used).max { sampleCounts[$0] < sampleCounts[$1] }!
                pixels.append(representatives[dominant])
            }
        }
        let colors = try quantize(pixels, limit: settings.colorCount)
        try applyPalette(&pixels, width: w, colors: colors, dither: settings.dither)
        return PixelResult(width: w, height: h, pixels: pixels)
    }

    static func reduce(_ result: PixelResult, limit: Int) throws -> PixelResult {
        var pixels = result.pixels
        let colors = try quantize(pixels, limit: max(2, min(64, limit)))
        try applyPalette(&pixels, width: result.width, colors: colors, dither: false)
        return PixelResult(width: result.width, height: result.height, pixels: pixels)
    }

    private static func nearest(_ value: SIMD3<Double>, colors: [RGBA]) -> RGBA {
        var best = colors[0], bestDistance = Double.infinity
        for color in colors {
            let delta = color.vector - value
            let distance = delta.x * delta.x + delta.y * delta.y + delta.z * delta.z
            if distance < bestDistance { best = color; bestDistance = distance }
        }
        return best
    }

    private static func applyPalette(_ pixels: inout [RGBA], width: Int, colors: [RGBA], dither: Bool) throws {
        guard !colors.isEmpty else { return }
        if !dither {
            var cache: [RGBA: RGBA] = [:]
            for i in pixels.indices {
                if i % width == 0 { try Task.checkCancellation() }
                let original = pixels[i]
                guard original.a > 0 else { continue }
                let selected: RGBA
                if let cached = cache[original] { selected = cached }
                else {
                    selected = nearest(original.vector, colors: colors)
                    cache[original] = selected
                }
                pixels[i] = RGBA(r: selected.r, g: selected.g, b: selected.b, a: original.a)
            }
            return
        }
        // Floyd–Steinberg only needs the current and next rows, including a one-cell halo.
        var current = [SIMD3<Double>](repeating: .zero, count: width + 2)
        var next = current
        for row in 0..<(pixels.count / width) {
            try Task.checkCancellation()
            for column in 0..<width {
                let i = row * width + column, original = pixels[i]
                guard original.a > 0 else { continue }
                let input = original.vector + current[column + 1]
                let adjusted = SIMD3(min(255, max(0, input.x)), min(255, max(0, input.y)), min(255, max(0, input.z)))
                let selected = nearest(adjusted, colors: colors)
                pixels[i] = RGBA(r: selected.r, g: selected.g, b: selected.b, a: original.a)
                let error = adjusted - selected.vector
                current[column + 2] += error * (7.0 / 16)
                next[column] += error * (3.0 / 16)
                next[column + 1] += error * (5.0 / 16)
                next[column + 2] += error * (1.0 / 16)
            }
            swap(&current, &next)
            for i in next.indices { next[i] = .zero }
        }
    }

    // Weighted median cut: frequent colors contribute proportionally to each representative.
    private static func quantize(_ pixels: [RGBA], limit: Int) throws -> [RGBA] {
        var histogram: [RGBA: Int] = [:]
        for p in pixels where p.a > 0 { histogram[RGBA(r: p.r, g: p.g, b: p.b), default: 0] += 1 }
        if histogram.count <= limit { return histogram.keys.sorted { $0.sortKey < $1.sortKey } }
        typealias Entry = (color: RGBA, count: Int)
        func channel(_ p: RGBA, _ index: Int) -> Int {
            switch index { case 0: Int(p.r); case 1: Int(p.g); default: Int(p.b) }
        }
        func spread(_ box: [Entry]) -> (range: Int, channel: Int) {
            var minimum = SIMD3<Int>(repeating: 255), maximum = SIMD3<Int>(repeating: 0)
            for entry in box {
                let p = entry.color
                minimum.x = min(minimum.x, Int(p.r)); maximum.x = max(maximum.x, Int(p.r))
                minimum.y = min(minimum.y, Int(p.g)); maximum.y = max(maximum.y, Int(p.g))
                minimum.z = min(minimum.z, Int(p.b)); maximum.z = max(maximum.z, Int(p.b))
            }
            let ranges = maximum &- minimum
            let selected = (0..<3).max { ranges[$0] < ranges[$1] }!
            return (ranges[selected], selected)
        }
        var boxes: [[Entry]] = [histogram.map { (color: $0.key, count: $0.value) }]
        var spreads = boxes.map(spread)
        while boxes.count < limit {
            try Task.checkCancellation()
            guard let index = boxes.indices.filter({ boxes[$0].count > 1 }).max(by: {
                spreads[$0].range < spreads[$1].range
            }) else { break }
            let selectedChannel = spreads.remove(at: index).channel
            let sorted = boxes.remove(at: index).sorted {
                let a = channel($0.color, selectedChannel), b = channel($1.color, selectedChannel)
                return a == b ? $0.color.sortKey < $1.color.sortKey : a < b
            }
            let half = sorted.reduce(0) { $0 + $1.count } / 2
            var sum = 0, split = 1
            for i in 0..<(sorted.count - 1) {
                sum += sorted[i].count; split = i + 1
                if sum >= half { break }
            }
            let left = Array(sorted[..<split]), right = Array(sorted[split...])
            boxes.append(left); boxes.append(right)
            spreads.append(spread(left)); spreads.append(spread(right))
        }
        return boxes.map { box in
            let total = box.reduce(0) { $0 + $1.count }
            let rgb = (0..<3).map { c in UInt8(box.reduce(0) { $0 + channel($1.color, c) * $1.count } / total) }
            return RGBA(r: rgb[0], g: rgb[1], b: rgb[2])
        }
    }
}
