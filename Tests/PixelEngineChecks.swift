import AppKit
import ImageIO
import PDFKit

@main
struct PixelEngineChecks {
    static func main() throws {
        try testRectangularCanvasAndPalette()
        try testExactDimensionsAndNearestNeighborExport()
        try testQuantizationAndDitheringRespectColorLimit()
        try testTransparentAndSinglePixelImages()
        try testFitLeavesTransparentMarginsAndFillCoversCanvas()
        try testInvalidSizesAndExportBounds()
        try testAllExportFormatsRoundTrip()
        try testDominantCellsKeepFlatColors()
        try testPatternRenderingAndExports()
        if CommandLine.arguments.count == 3 {
            try exportExample(input: CommandLine.arguments[1], directory: CommandLine.arguments[2])
        }
        print("✓ 9 comprobaciones: dimensiones, orientación, paleta, tramado, transparencia, límites y exportación PNG/JPG/PDF")
    }
    private static func fixture() throws -> CGImage {
        // Distinct quadrants expose flips, interpolation and unintended palette changes.
        let pixels = [RGBA(r: 255, g: 0, b: 0), RGBA(r: 0, g: 255, b: 0),
                      RGBA(r: 0, g: 0, b: 255), RGBA(r: 0, g: 0, b: 0, a: 0)]
        return try PixelResult(width: 2, height: 2, pixels: pixels, palette: []).cgImage()
    }

    static func testRectangularCanvasAndPalette() throws {
        let options = PixelSettings(width: 23, height: 49, colorCount: 4, fit: .stretch, smooth: false)
        let result = try PixelEngine.render(source: fixture(), settings: options)
        expectEqual(result.width, 23)
        expectEqual(result.height, 49)
        expectEqual(result.pixels.count, 23 * 49)
        expectEqual(Set(result.palette.map(\.color.hex)), ["#FF0000", "#00FF00", "#0000FF"])
        expectEqual(result.pixels.first?.hex, "#FF0000")
        expectEqual(result.pixels[22].hex, "#00FF00")
        expectEqual(result.pixels[48 * 23].hex, "#0000FF")
        expectEqual(result.pixels.last?.a, 0)
        expectEqual(result.palette.reduce(0) { $0 + $1.count }, result.pixels.filter { $0.a > 0 }.count)
    }

    static func testExactDimensionsAndNearestNeighborExport() throws {
        let source = try fixture()
        let result = try PixelEngine.render(source: source, settings: PixelSettings(width: 2, height: 2, colorCount: 4, smooth: false))
        let expanded = try result.cgImage(scale: 10)
        expectEqual(expanded.width, 20)
        expectEqual(expanded.height, 20)
        let roundtrip = try PixelEngine.render(source: expanded, settings: PixelSettings(width: 2, height: 2, colorCount: 4, smooth: false))
        expectEqual(result.pixels, roundtrip.pixels)
    }

    static func testQuantizationAndDitheringRespectColorLimit() throws {
        let colors = (0..<256).map { RGBA(r: UInt8($0), g: UInt8(255 - $0), b: UInt8($0 / 2)) }
        let source = try PixelResult(width: 16, height: 16, pixels: colors, palette: []).cgImage()
        for dither in [false, true] {
            let result = try PixelEngine.render(source: source, settings: PixelSettings(width: 16, height: 16, colorCount: 8, dither: dither))
            expectAtMost(result.palette.count, 8)
            expectGreater(result.palette.count, 1)
            expectEqual(result.palette.reduce(0) { $0 + $1.count }, 256)
        }
    }

    static func testTransparentAndSinglePixelImages() throws {
        for alpha: UInt8 in [0, 128, 255] {
            let image = try PixelResult(width: 1, height: 1, pixels: [RGBA(r: 200, g: 100, b: 40, a: alpha)], palette: []).cgImage()
            let output = try PixelEngine.render(source: image, settings: PixelSettings(width: 1, height: 1, flatColors: false))
            expectEqual(output.pixels[0].a, alpha)
            expectEqual(output.palette.count, alpha == 0 ? 0 : 1)
        }
    }

    static func testFitLeavesTransparentMarginsAndFillCoversCanvas() throws {
        let source = try PixelResult(width: 4, height: 1, pixels: Array(repeating: RGBA(r: 255, g: 0, b: 0), count: 4), palette: []).cgImage()
        let fit = try PixelEngine.render(source: source, settings: PixelSettings(width: 4, height: 4, smooth: false))
        expectTrue(fit.pixels.contains { $0.a == 0 })
        let fill = try PixelEngine.render(source: source, settings: PixelSettings(width: 4, height: 4, fit: .fill, smooth: false))
        expectTrue(fill.pixels.allSatisfy { $0.a == 255 })
    }

    static func testInvalidSizesAndExportBounds() throws {
        for size in [0, -1, 513, Int.max] {
            expectThrows(try PixelEngine.render(source: fixture(), settings: PixelSettings(width: size)))
        }
        let result = PixelResult(width: 512, height: 1, pixels: Array(repeating: RGBA(r: 0, g: 0, b: 0), count: 512), palette: [])
        expectThrows(try result.cgImage(scale: 17))
        expectThrows(try result.cgImage(scale: 0))
    }

    static func testAllExportFormatsRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try PixelEngine.render(source: fixture(), settings: PixelSettings(width: 2, height: 2, colorCount: 4, smooth: false))
        for format in ExportFormat.allCases {
            let url = directory.appendingPathComponent("export.\(format.ext)")
            try ImageExporter.write(result, format: format, scale: 10, to: url)
            if format == .pdf {
                let pdf = try unwrap(PDFDocument(url: url))
                expectEqual(pdf.pageCount, 1)
                expectEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 20, height: 20))
            } else {
                let loaded = try PixelEngine.load(url: url)
                expectEqual(loaded.image.width, 20)
                expectEqual(loaded.image.height, 20)
                let sampled = try PixelEngine.render(source: loaded.image, settings: PixelSettings(width: 2, height: 2, colorCount: 4, smooth: false))
                if format == .png {
                    expectEqual(sampled.pixels, result.pixels)
                } else {
                    expectTrue(sampled.pixels.allSatisfy { $0.a == 255 })
                    expectGreater(sampled.pixels.last!.r, 240)
                    expectGreater(sampled.pixels.last!.g, 240)
                    expectGreater(sampled.pixels.last!.b, 240)
                }
            }
        }
    }
    static func testDominantCellsKeepFlatColors() throws {
        var pixels = Array(repeating: RGBA(r: 255, g: 255, b: 0), count: 16)
        for i in 0..<4 { pixels[i] = RGBA(r: 0, g: 0, b: 255) }
        let image = try PixelResult(width: 4, height: 4, pixels: pixels, palette: []).cgImage()
        let result = try PixelEngine.render(source: image, settings: PixelSettings(width: 1, height: 1))
        expectEqual(result.pixels[0], RGBA(r: 255, g: 255, b: 0))
        let alphaImage = try PixelResult(width: 1, height: 1, pixels: [RGBA(r: 255, g: 0, b: 0, a: 200)], palette: []).cgImage()
        let solid = try PixelEngine.render(source: alphaImage, settings: PixelSettings(width: 1, height: 1))
        expectEqual(solid.pixels[0].a, 255)
    }

    static func testPatternRenderingAndExports() throws {
        let result = try PixelEngine.render(source: fixture(), settings: PixelSettings(width: 2, height: 2, colorCount: 4))
        let options = PatternOptions()
        let image = try PatternRenderer.image(result, cellSize: 16, options: options)
        expectEqual(image.width, 96)
        expectEqual(image.height, 96)
        let data = image.dataProvider!.data! as Data
        func colorAt(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = y * image.bytesPerRow + x * 4
            return Array(data[offset..<(offset + 4)])
        }
        expectEqual(colorAt(40, 40), [255, 0, 0, 255])
        expectEqual(colorAt(56, 40), [0, 255, 0, 255])
        expectEqual(colorAt(40, 56), [0, 0, 255, 255])
        expectEqual(colorAt(56, 56), [255, 255, 255, 255])
        expectTrue(colorAt(48, 56)[0] < 255) // Grid runs through empty cells too.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for format in ExportFormat.allCases {
            let url = directory.appendingPathComponent("pattern.\(format.ext)")
            try ImageExporter.write(result, format: format, scale: 16, to: url, pattern: options)
            if format == .pdf {
                let pdf = try unwrap(PDFDocument(url: url))
                expectEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 96, height: 96))
                expectTrue(pdf.string?.contains("2") == true)
            } else {
                let loaded = try PixelEngine.load(url: url)
                expectEqual(loaded.image.width, 96)
                expectEqual(loaded.image.height, 96)
            }
        }
        let withoutCoordinates = try PatternRenderer.image(result, cellSize: 16, options: PatternOptions(grid: false, coordinates: false))
        expectEqual(withoutCoordinates.width, 56)
        expectThrows(try PatternRenderer.image(result, cellSize: 33, options: options))
        let large = PixelResult(width: 512, height: 1, pixels: Array(repeating: RGBA(r: 0, g: 0, b: 0), count: 512), palette: [])
        expectThrows(try PatternRenderer.image(large, cellSize: 16, options: options))
    }

    static func exportExample(input: String, directory: String) throws {
        let source = try PixelEngine.load(url: URL(fileURLWithPath: input))
        let result = try PixelEngine.render(source: source.image, settings: PixelSettings())
        let folder = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for format in ExportFormat.allCases {
            try ImageExporter.write(result, format: format, scale: 20,
                                    to: folder.appendingPathComponent("PaTico-JeXelart-48x48.\(format.ext)"), pattern: PatternOptions())
        }
        print("✓ Ejemplo generado en \(folder.path)")
    }

}

// A small throwing-free assertion harness keeps checks runnable with Command Line Tools alone.
private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    precondition(actual == expected, "Expected \(expected), received \(actual)", file: file, line: line)
}
private func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
private func expectAtMost<T: Comparable>(_ actual: T, _ limit: T, file: StaticString = #file, line: UInt = #line) {
    precondition(actual <= limit, "Value exceeds limit", file: file, line: line)
}
private func expectGreater<T: Comparable>(_ actual: T, _ limit: T, file: StaticString = #file, line: UInt = #line) {
    precondition(actual > limit, "Value should exceed limit", file: file, line: line)
}
private func expectThrows(_ expression: @autoclosure () throws -> Any, file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression() } catch { return }
    preconditionFailure("Expected an error", file: file, line: line)
}
private func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw PixelError.invalidImage }
    return value
}
