import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let jexelartPattern = UTType(exportedAs: "com.jevstudio.jexelart.pattern", conformingTo: .json)
}

struct CellAddress: Equatable {
    let row: Int
    let column: Int
}

struct GridGeometry {
    // Coordinates start at the top left of the sheet, including its margin.
    static func cell(at point: CGPoint, width: Int, height: Int, cellSize: CGFloat, margin: CGFloat) -> CellAddress? {
        let x = point.x - margin, y = point.y - margin
        guard cellSize > 0, x >= 0, y >= 0,
              x < CGFloat(width) * cellSize, y < CGFloat(height) * cellSize else { return nil }
        return CellAddress(row: Int(y / cellSize), column: Int(x / cellSize))
    }
}

enum CellTool: String, CaseIterable, Identifiable {
    case pencil = "Lápiz", eraser = "Borrador", eyedropper = "Cuentagotas", fill = "Bote"
    var id: String { rawValue }
}

struct CellChange: Equatable {
    let row: Int
    let column: Int
    let before: RGBA
    var after: RGBA
}

// One transaction per stroke, storing only the cells changed by that action.
struct GridHistory {
    private var past: [[CellChange]] = []
    private var future: [[CellChange]] = []
    private var pending: [Int: CellChange] = [:]
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    mutating func set(_ color: RGBA, row: Int, column: Int, in result: inout PixelResult) {
        guard row >= 0, row < result.height, column >= 0, column < result.width else { return }
        let before = result[row, column]
        result[row, column] = color
        let after = result[row, column]
        guard before != after else { return }
        let key = row * result.width + column
        if var change = pending[key] { change.after = after; pending[key] = change }
        else { pending[key] = CellChange(row: row, column: column, before: before, after: after) }
    }

    mutating func fill(_ color: RGBA, row: Int, column: Int, in result: inout PixelResult) {
        guard row >= 0, row < result.height, column >= 0, column < result.width else { return }
        let target = result[row, column]
        let solid = color.a == 0 ? RGBA(r: 0, g: 0, b: 0, a: 0) : RGBA(r: color.r, g: color.g, b: color.b)
        guard target != solid else { return }
        var stack = [(row, column)]
        while let (r, c) = stack.popLast() {
            guard r >= 0, r < result.height, c >= 0, c < result.width, result[r, c] == target else { continue }
            set(solid, row: r, column: c, in: &result)
            stack.append(contentsOf: [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)])
        }
    }

    mutating func commit() {
        let changes = pending.values.filter { $0.before != $0.after }
        pending.removeAll()
        guard !changes.isEmpty else { return }
        past.append(changes); future.removeAll()
        if past.count > 100 { past.removeFirst() }
    }

    mutating func undo(in result: inout PixelResult) {
        commit()
        guard let changes = past.popLast() else { return }
        for change in changes { result[change.row, change.column] = change.before }
        future.append(changes)
    }

    mutating func redo(in result: inout PixelResult) {
        guard let changes = future.popLast() else { return }
        for change in changes { result[change.row, change.column] = change.after }
        past.append(changes)
    }
}

struct GridDocument: Codable {
    var version = 1
    var settings: PixelSettings
    var grid: [[RGBA]]
    var options: PatternOptions

    func validatedResult() throws -> PixelResult {
        guard version == 1, settings.isValid, grid.count == settings.height,
              grid.allSatisfy({ $0.count == settings.width && $0.allSatisfy { $0.a == 0 || $0.a == 255 } })
        else { throw PixelError.invalidImage }
        return PixelResult(width: settings.width, height: settings.height, pixels: grid.flatMap { $0 })
    }

    static func read(from url: URL) throws -> GridDocument {
        let document = try JSONDecoder().decode(GridDocument.self, from: Data(contentsOf: url))
        _ = try document.validatedResult()
        return document
    }

    func write(to url: URL) throws {
        _ = try validatedResult()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
