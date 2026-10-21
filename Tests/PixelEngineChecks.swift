import AppKit
import ImageIO
import PDFKit

@main
struct PixelEngineChecks {
    @MainActor static func main() async throws {
        try testRectangularCanvasAndPalette()
        try testExactDimensionsAndNearestNeighborExport()
        try testQuantizationAndDitheringRespectColorLimit()
        try testTransparentAndSinglePixelImages()
        try testFitLeavesTransparentMarginsAndFillCoversCanvas()
        try testInvalidSizesAndExportBounds()
        try testAllExportFormatsRoundTrip()
        try testDominantCellsKeepFlatColors()
        try testPatternRenderingAndExports()
        try testSymbolsAndPerColorVisibility()
        testUniqueSymbolAssignments()
        try testRequestedDimensionsAndSolidCells()
        testCellEditingAndHistory()
        testCellHitTesting()
        try testEditableDocument()
        try testSharpRasterColors()
        try await testAppEditingAndImport()
        if CommandLine.arguments.count == 3 {
            try exportExample(input: CommandLine.arguments[1], directory: CommandLine.arguments[2])
        }
        print("✓ 17 comprobaciones: dimensiones exactas, celdas sólidas, edición, historial, coordenadas, archivo editable y exportaciones")
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
            expectEqual(output.pixels[0].a, alpha >= 128 ? 255 : 0)
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
        let nearBlack = try PixelResult(width: 2, height: 1,
                                       pixels: [RGBA(r: 0, g: 0, b: 0), RGBA(r: 3, g: 6, b: 8)], palette: []).cgImage()
        let clean = try PixelEngine.render(source: nearBlack, settings: PixelSettings(width: 2, height: 1))
        expectEqual(clean.palette.count, 1)
        expectEqual(clean.palette[0].color.hex, "#000000")
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

    static func testUniqueSymbolAssignments() {
        expectEqual(PatternOptions.symbols.count, 64)
        expectEqual(Set(PatternOptions.symbols).count, 64)
        let palette = (0..<64).map { PaletteColor(color: RGBA(r: UInt8($0 * 4), g: 0, b: 0), count: 1) }
        var options = PatternOptions()
        options.symbolAssignments[palette[30].color] = "♥"
        let assigned = options.resolvedSymbols(for: palette)
        expectEqual(assigned.count, 64)
        expectEqual(Set(assigned.values).count, 64)
        expectEqual(assigned[palette[30].color], "♥")
        let reordered = options.resolvedSymbols(for: Array(palette.reversed()))
        expectEqual(reordered[palette[30].color], "♥")
        expectTrue(PatternOptions.usesLightInk(for: RGBA(r: 0, g: 0, b: 0)))
        expectTrue(!PatternOptions.usesLightInk(for: RGBA(r: 255, g: 255, b: 0)))
        expectTrue(!PatternOptions.usesLightInk(for: RGBA(r: 0, g: 0, b: 0, a: 0)))
    }

    static func testSymbolsAndPerColorVisibility() throws {
        let black = RGBA(r: 0, g: 0, b: 0), yellow = RGBA(r: 255, g: 255, b: 0), white = RGBA(r: 255, g: 255, b: 255)
        let result = PixelResult(width: 2, height: 2,
                                 pixels: [black, yellow, white, RGBA(r: 0, g: 0, b: 0, a: 0)],
                                 palette: [black, yellow, white].map { PaletteColor(color: $0, count: 1) })
        let plain = PatternOptions(grid: false, coordinates: false)
        var options = plain
        options.symbolsEnabled = true
        options.symbolAssignments = [black: "□", yellow: "×", white: "○"]
        let base = try PatternRenderer.image(result, cellSize: 32, options: plain)
        let marked = try PatternRenderer.image(result, cellSize: 32, options: options)
        func cellBytes(_ image: CGImage, col: Int, row: Int) -> [UInt8] {
            let data = image.dataProvider!.data! as Data
            return (0..<32).flatMap { y -> [UInt8] in
                let start = (12 + row * 32 + y) * image.bytesPerRow + (12 + col * 32) * 4
                return Array(data[start..<(start + 32 * 4)])
            }
        }
        for (col, row) in [(0, 0), (1, 0), (0, 1)] {
            expectTrue(cellBytes(base, col: col, row: row) != cellBytes(marked, col: col, row: row))
        }
        expectEqual(cellBytes(base, col: 1, row: 1), cellBytes(marked, col: 1, row: 1))
        options.hiddenSymbolColors.insert(yellow)
        let hidden = try PatternRenderer.image(result, cellSize: 32, options: options)
        expectEqual(cellBytes(base, col: 1, row: 0), cellBytes(hidden, col: 1, row: 0))
        expectTrue(cellBytes(base, col: 0, row: 0) != cellBytes(hidden, col: 0, row: 0))
        options.symbolsEnabled = false
        let disabled = try PatternRenderer.image(result, cellSize: 32, options: options)
        expectEqual(disabled.dataProvider!.data! as Data, base.dataProvider!.data! as Data)
        options.symbolsEnabled = true
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for format in ExportFormat.allCases {
            let url = directory.appendingPathComponent("symbols.\(format.ext)")
            try ImageExporter.write(result, format: format, scale: 32, to: url, pattern: options)
            if format == .pdf {
                let pdf = try unwrap(PDFDocument(url: url))
                expectTrue(pdf.string?.contains("□") == true)
                expectTrue(pdf.string?.contains("×") == false)
            } else {
                let loaded = try PixelEngine.load(url: url)
                expectEqual(loaded.image.width, marked.width)
                expectEqual(loaded.image.height, marked.height)
            }
        }
    }

    static func testRequestedDimensionsAndSolidCells() throws {
        for (width, height, count) in [(25, 25, 625), (30, 50, 1500), (40, 40, 1600), (43, 62, 2666), (1, 512, 512)] {
            for fit in ImageFit.allCases {
                let result = try PixelEngine.render(source: fixture(), settings: PixelSettings(width: width, height: height, fit: fit))
                expectEqual(result.width, width); expectEqual(result.height, height)
                expectEqual(result.grid.count, height)
                expectTrue(result.grid.allSatisfy { $0.count == width })
                expectEqual(result.pixels.count, count)
                expectTrue(result.pixels.allSatisfy { $0.a == 0 || $0.a == 255 })
                let image = try result.cgImage(scale: 3)
                expectEqual(image.width, width * 3); expectEqual(image.height, height * 3)
            }
        }
    }

    static func testCellEditingAndHistory() {
        let red = RGBA(r: 255, g: 0, b: 0), blue = RGBA(r: 0, g: 0, b: 255)
        let empty = RGBA(r: 0, g: 0, b: 0, a: 0)
        var result = PixelResult(width: 3, height: 2, pixels: [red, blue, red, red, blue, red])
        var history = GridHistory()
        history.set(blue, row: 0, column: 0, in: &result)
        history.set(empty, row: 0, column: 0, in: &result)
        history.commit()
        expectEqual(result.pixels, [empty, blue, red, red, blue, red])
        expectEqual(result.palette.first?.count, 3)
        history.undo(in: &result); expectEqual(result[0, 0], red)
        history.redo(in: &result); expectEqual(result[0, 0], empty)
        history.fill(blue, row: 1, column: 2, in: &result); history.commit()
        expectEqual(result.pixels, [empty, blue, blue, red, blue, blue])
        history.undo(in: &result); expectEqual(result.pixels, [empty, blue, red, red, blue, red])
        history.set(red, row: 0, column: 0, in: &result); history.commit()
        expectTrue(!history.canRedo)
        history.set(blue, row: -1, column: 0, in: &result)
        history.fill(red, row: 1, column: 3, in: &result)
        expectEqual(result.pixels, [red, blue, red, red, blue, red])
        // Diagonals must not be included by a contiguous fill.
        var diagonal = PixelResult(width: 2, height: 2, pixels: [red, blue, blue, red])
        history = GridHistory()
        history.fill(empty, row: 0, column: 0, in: &diagonal); history.commit()
        expectEqual(diagonal.pixels, [empty, blue, blue, red])
        let reduced = PixelEngine.reduce(result, limit: 2)
        expectAtMost(reduced.palette.count, 2)
        expectEqual(reduced.width, result.width); expectEqual(reduced.height, result.height)
    }

    static func testCellHitTesting() {
        for cell: CGFloat in [1, 8, 32, 128] {
            expectEqual(GridGeometry.cell(at: CGPoint(x: 32, y: 32), width: 25, height: 25, cellSize: cell, margin: 32), CellAddress(row: 0, column: 0))
            expectEqual(GridGeometry.cell(at: CGPoint(x: 32 + cell * 24.5, y: 32 + cell * 24.5), width: 25, height: 25, cellSize: cell, margin: 32), CellAddress(row: 24, column: 24))
            expectEqual(GridGeometry.cell(at: CGPoint(x: 31, y: 32), width: 25, height: 25, cellSize: cell, margin: 32), nil)
            expectEqual(GridGeometry.cell(at: CGPoint(x: 32 + cell * 25, y: 32), width: 25, height: 25, cellSize: cell, margin: 32), nil)
        }
    }

    static func testEditableDocument() throws {
        let result = try PixelEngine.render(source: fixture(), settings: PixelSettings(width: 43, height: 62))
        var options = PatternOptions(symbolsEnabled: true)
        options.background = RGBA(r: 220, g: 230, b: 240)
        options.symbolAssignments[result.palette[0].color] = "♥"
        options.hiddenSymbolColors.insert(result.palette[0].color)
        let document = GridDocument(settings: PixelSettings(width: 43, height: 62), grid: result.grid, options: options)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jexelart")
        defer { try? FileManager.default.removeItem(at: url) }
        try document.write(to: url)
        let loaded = try GridDocument.read(from: url)
        expectEqual(try loaded.validatedResult(), result)
        expectEqual(loaded.options, options)
        expectEqual(loaded.settings, document.settings)
        var invalid = document
        invalid.grid.removeLast(); expectThrows(try invalid.validatedResult())
        invalid = document; invalid.grid[0].removeLast(); expectThrows(try invalid.validatedResult())
        invalid = document; invalid.settings.width = Int.max; expectThrows(try invalid.validatedResult())
        invalid = document; invalid.grid[0][0].a = 128; expectThrows(try invalid.validatedResult())
        invalid = document; invalid.version = 2; expectThrows(try invalid.validatedResult())
    }

    static func testSharpRasterColors() throws {
        let result = try PixelEngine.render(source: fixture(), settings: PixelSettings(width: 2, height: 2))
        var plain = PatternOptions(grid: false, coordinates: false)
        plain.background = RGBA(r: 250, g: 240, b: 230)
        let allowed: Set<[UInt8]> = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [250, 240, 230, 255]]
        for grid in [false, true] {
            plain.grid = grid
            let image = try PatternRenderer.image(result, cellSize: 16, options: plain)
            let data = image.dataProvider!.data! as Data
            var actual: Set<[UInt8]> = []
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let i = y * image.bytesPerRow + x * 4
                    actual.insert(Array(data[i..<(i + 4)]))
                }
            }
            let expected = grid ? allowed.union([[64, 64, 64, 255]]) : allowed
            expectEqual(actual, expected)
        }
        let image = try result.cgImage(scale: 7)
        let data = image.dataProvider!.data! as Data
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = result[y / 7, x / 7]
                let i = y * image.bytesPerRow + x * 4
                expectEqual(Array(data[i..<(i + 4)]), [p.r, p.g, p.b, p.a])
            }
        }
    }

    @MainActor static func testAppEditingAndImport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vertical = PixelResult(width: 1, height: 4, pixels: Array(repeating: RGBA(r: 255, g: 0, b: 0), count: 4))
        let imageURL = folder.appendingPathComponent("vertical.png")
        try ImageExporter.write(vertical, format: .png, scale: 1, to: imageURL)
        let model = AppModel()
        model.settings.width = 25; model.settings.height = 25
        model.load(imageURL)
        for _ in 0..<250 {
            if !model.busy { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        expectTrue(!model.busy); expectEqual(model.error, nil)
        expectEqual(model.settings.width, 25); expectEqual(model.settings.height, 25)
        expectEqual(model.result?.pixels.count, 625)
        let before = try unwrap(model.result)
        let blue = RGBA(r: 0, g: 0, b: 255)
        model.select(blue)
        model.edit(row: 0, column: 0, initial: true); model.endStroke()
        expectEqual(model.result?[0, 0], blue)
        expectEqual(model.result?[0, 1], before[0, 1])
        model.tool = .eyedropper
        model.select(RGBA(r: 0, g: 255, b: 0))
        model.edit(row: 0, column: 0, initial: true)
        expectEqual(model.paintColor, blue)
        model.undo(); expectEqual(model.result, before)
        model.redo(); expectEqual(model.result?[0, 0], blue)
        model.tool = .eraser; model.edit(row: 0, column: 0, initial: true); model.endStroke()
        expectEqual(model.result?[0, 0].a, 0)
        model.undo(); expectEqual(model.result?[0, 0], blue)
        model.select(RGBA(r: 0, g: 255, b: 0)); model.replaceColor(blue)
        expectEqual(model.result?[0, 0].hex, "#00FF00")
        model.undo(); expectEqual(model.result?[0, 0], blue)
        // Opening an editable file with identical settings must keep the edited matrix.
        let edited = try unwrap(model.result)
        let documentURL = folder.appendingPathComponent("edited.jexelart")
        try GridDocument(settings: model.settings, grid: edited.grid, options: model.patternOptions).write(to: documentURL)
        model.load(documentURL)
        expectEqual(model.result, edited); expectTrue(model.source == nil)
        model.patternOptions.grid.toggle(); model.patternOptions.coordinates.toggle()
        expectEqual(model.result, edited)
        let old = model.settings
        model.settings.colorCount = 2; model.settingsChanged(from: old)
        expectEqual(model.result?.width, 25); expectEqual(model.result?.height, 25)
        expectAtMost(model.result!.palette.count, 2)
    }

    static func exportExample(input: String, directory: String) throws {
        let source = try PixelEngine.load(url: URL(fileURLWithPath: input))
        let result = try PixelEngine.render(source: source.image, settings: PixelSettings())
        let folder = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for format in ExportFormat.allCases {
            try ImageExporter.write(result, format: format, scale: 20,
                                    to: folder.appendingPathComponent("PaTico-JeXelart-48x48.\(format.ext)"), pattern: PatternOptions())
            try ImageExporter.write(result, format: format, scale: 24,
                                    to: folder.appendingPathComponent("PaTico-JeXelart-simbolos-48x48.\(format.ext)"),
                                    pattern: PatternOptions(symbolsEnabled: true))
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
