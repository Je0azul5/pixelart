import AppKit

// Run each scenario in a fresh optimized process; /usr/bin/time -l reports peak RSS.
@main
struct PerformanceChecks {
    static func main() throws {
        let scenario = CommandLine.arguments.dropFirst().first ?? "convert"
        let red = RGBA(r: 255, g: 0, b: 0)
        let blue = RGBA(r: 0, g: 0, b: 255)
        let cells = (0..<(512 * 512)).map { i in i % 512 < 256 ? red : blue }
        let result = PixelResult(width: 512, height: 512, pixels: cells)
        let start = CFAbsoluteTimeGetCurrent()
        var checksum = 0
        switch scenario {
        case "convert", "dither":
            let gradient: [RGBA] = (0..<262144).map { i -> RGBA in
                let r = UInt8(i % 256), g = UInt8((i / 512) % 256), b = UInt8((i / 64) % 256)
                return RGBA(r: r, g: g, b: b)
            }
            let source = try PixelResult(width: 512, height: 512, pixels: gradient).cgImage()
            let output = try PixelEngine.render(source: source, settings: PixelSettings(width: 512, height: 512, colorCount: 32, dither: scenario == "dither"))
            checksum = output.palette.reduce(0) { $0 + $1.count }
        case "fingerprints":
            let input: [RGBA] = (0..<2048).map { i -> RGBA in
                let r = UInt8(i % 256), g = UInt8((i / 8) % 256), b = UInt8((i / 16) % 256)
                let alpha: UInt8 = i % 7 == 0 ? 0 : 255
                return RGBA(r: r, g: g, b: b, a: alpha)
            }
            let source = try PixelResult(width: 64, height: 32, pixels: input).cgImage()
            for flat in [false, true] {
                for dither in [false, true] {
                    for fit in ImageFit.allCases {
                        let output = try PixelEngine.render(source: source, settings: PixelSettings(width: 43, height: 62, colorCount: 8, fit: fit, dither: dither, flatColors: flat))
                        var hash: UInt64 = 14695981039346656037
                        for p in output.pixels {
                            for byte in [p.r, p.g, p.b, p.a] { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
                        }
                        print("\(flat) \(dither) \(fit): \(hash)")
                    }
                }
            }
        case "palette":
            for _ in 0..<200 { checksum += result.palette.reduce(0) { $0 + $1.count } }
        case "clipped":
            let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            for _ in 0..<20 { PatternRenderer.draw(result, in: context, cellSize: 16, options: PatternOptions(coordinates: false)) }
            checksum = context.makeImage()!.width
        case "history":
            var edited = result
            var history = GridHistory()
            for step in 0..<24 {
                let color = step.isMultiple(of: 2) ? blue : red
                for row in 0..<512 { for col in 0..<512 { history.set(color, row: row, column: col, in: &edited) } }
                history.commit()
            }
            checksum = edited.palette.reduce(0) { $0 + $1.count }
        case "pdf":
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            defer { try? FileManager.default.removeItem(at: url) }
            try ImageExporter.write(result, format: .pdf, scale: 15, to: url, pattern: PatternOptions(coordinates: false))
            checksum = (try Data(contentsOf: url)).count
        default: preconditionFailure("Unknown scenario")
        }
        print(String(format: "%@: %.4f s; checksum %d", scenario, CFAbsoluteTimeGetCurrent() - start, checksum))
    }
}
