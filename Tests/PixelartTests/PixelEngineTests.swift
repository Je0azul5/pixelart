import XCTest
import AppKit
import ImageIO
import PDFKit
@testable import Pixelart

final class PixelEngineTests: XCTestCase {
    private func fixture() throws -> CGImage {
        // Distinct quadrants expose flips, interpolation and unintended palette changes.
        let pixels = [RGBA(r: 255, g: 0, b: 0), RGBA(r: 0, g: 255, b: 0),
                      RGBA(r: 0, g: 0, b: 255), RGBA(r: 0, g: 0, b: 0, a: 0)]
        return try PixelResult(width: 2, height: 2, pixels: pixels, palette: []).cgImage()
    }

    func testRectangularCanvasAndPalette() throws {
        let options = PixelSettings(width: 23, height: 49, colorCount: 4, fit: .stretch, smooth: false)
        let result = try PixelEngine.render(source: fixture(), settings: options)
        XCTAssertEqual(result.width, 23)
        XCTAssertEqual(result.height, 49)
        XCTAssertEqual(result.pixels.count, 23 * 49)
        XCTAssertEqual(Set(result.palette.map(\.color.hex)), ["#FF0000", "#00FF00", "#0000FF"])
        XCTAssertEqual(result.pixels.first?.hex, "#FF0000")
        XCTAssertEqual(result.pixels[22].hex, "#00FF00")
        XCTAssertEqual(result.pixels[48 * 23].hex, "#0000FF")
        XCTAssertEqual(result.pixels.last?.a, 0)
        XCTAssertEqual(result.palette.reduce(0) { $0 + $1.count }, result.pixels.filter { $0.a > 0 }.count)
    }

    func testExactDimensionsAndNearestNeighborExport() throws {
        let source = try fixture()
        let result = try PixelEngine.render(source: source, settings: PixelSettings(width: 2, height: 2, colorCount: 4, smooth: false))
        let expanded = try result.cgImage(scale: 10)
        XCTAssertEqual(expanded.width, 20)
        XCTAssertEqual(expanded.height, 20)
        let roundtrip = try PixelEngine.render(source: expanded, settings: PixelSettings(width: 2, height: 2, colorCount: 4, smooth: false))
        XCTAssertEqual(result.pixels, roundtrip.pixels)
    }

    func testQuantizationAndDitheringRespectColorLimit() throws {
        let colors = (0..<256).map { RGBA(r: UInt8($0), g: UInt8(255 - $0), b: UInt8($0 / 2)) }
        let source = try PixelResult(width: 16, height: 16, pixels: colors, palette: []).cgImage()
        for dither in [false, true] {
            let result = try PixelEngine.render(source: source, settings: PixelSettings(width: 16, height: 16, colorCount: 8, dither: dither))
            XCTAssertLessThanOrEqual(result.palette.count, 8)
            XCTAssertGreaterThan(result.palette.count, 1)
            XCTAssertEqual(result.palette.reduce(0) { $0 + $1.count }, 256)
        }
    }

    func testTransparentAndSinglePixelImages() throws {
        for alpha: UInt8 in [0, 128, 255] {
            let image = try PixelResult(width: 1, height: 1, pixels: [RGBA(r: 200, g: 100, b: 40, a: alpha)], palette: []).cgImage()
            let output = try PixelEngine.render(source: image, settings: PixelSettings(width: 1, height: 1))
            XCTAssertEqual(output.pixels[0].a, alpha)
            XCTAssertEqual(output.palette.count, alpha == 0 ? 0 : 1)
        }
    }

    func testFitLeavesTransparentMarginsAndFillCoversCanvas() throws {
        let source = try PixelResult(width: 4, height: 1, pixels: Array(repeating: RGBA(r: 255, g: 0, b: 0), count: 4), palette: []).cgImage()
        let fit = try PixelEngine.render(source: source, settings: PixelSettings(width: 4, height: 4, smooth: false))
        XCTAssertTrue(fit.pixels.contains { $0.a == 0 })
        let fill = try PixelEngine.render(source: source, settings: PixelSettings(width: 4, height: 4, fit: .fill, smooth: false))
        XCTAssertTrue(fill.pixels.allSatisfy { $0.a == 255 })
    }

    func testInvalidSizesAndExportBounds() throws {
        for size in [0, -1, 513, Int.max] {
            XCTAssertThrowsError(try PixelEngine.render(source: fixture(), settings: PixelSettings(width: size)))
        }
        let result = PixelResult(width: 512, height: 1, pixels: Array(repeating: RGBA(r: 0, g: 0, b: 0), count: 512), palette: [])
        XCTAssertThrowsError(try result.cgImage(scale: 17))
        XCTAssertThrowsError(try result.cgImage(scale: 0))
    }

    func testAllExportFormatsRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try PixelEngine.render(source: fixture(), settings: PixelSettings(width: 2, height: 2, colorCount: 4, smooth: false))
        for format in ExportFormat.allCases {
            let url = directory.appendingPathComponent("export.\(format.ext)")
            try ImageExporter.write(result, format: format, scale: 10, to: url)
            if format == .pdf {
                let pdf = try XCTUnwrap(PDFDocument(url: url))
                XCTAssertEqual(pdf.pageCount, 1)
                XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 20, height: 20))
            } else {
                let loaded = try PixelEngine.load(url: url)
                XCTAssertEqual(loaded.image.width, 20)
                XCTAssertEqual(loaded.image.height, 20)
                let sampled = try PixelEngine.render(source: loaded.image, settings: PixelSettings(width: 2, height: 2, colorCount: 4, smooth: false))
                if format == .png {
                    XCTAssertEqual(sampled.pixels, result.pixels)
                } else {
                    XCTAssertTrue(sampled.pixels.allSatisfy { $0.a == 255 })
                    XCTAssertGreaterThan(sampled.pixels.last!.r, 240)
                    XCTAssertGreaterThan(sampled.pixels.last!.g, 240)
                    XCTAssertGreaterThan(sampled.pixels.last!.b, 240)
                }
            }
        }
    }
}
