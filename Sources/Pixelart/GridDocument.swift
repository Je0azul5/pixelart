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
    private let address: UInt32
    let before: RGBA
    var after: RGBA
    var row: Int { Int(address >> 16) }
    var column: Int { Int(address & 0xFFFF) }

    init(row: Int, column: Int, before: RGBA, after: RGBA) {
        address = UInt32(row) << 16 | UInt32(column)
        self.before = before; self.after = after
    }
}

// One transaction per stroke, storing only the cells changed by that action.
struct GridHistory {
    private var past: [[CellChange]] = []
    private var future: [[CellChange]] = []
    private var pending: [Int: CellChange] = [:]
    private let byteLimit: Int
    private var retainedChanges = 0
    var retainedBytes: Int { retainedChanges * MemoryLayout<CellChange>.stride }

    init(byteLimit: Int = 16 * 1024 * 1024) { self.byteLimit = max(0, byteLimit) }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    @discardableResult mutating func set(_ color: RGBA, row: Int, column: Int, in result: inout PixelResult) -> Bool {
        guard row >= 0, row < result.height, column >= 0, column < result.width else { return false }
        let before = result[row, column]
        let after = color.a == 0 ? RGBA(r: 0, g: 0, b: 0, a: 0) : RGBA(r: color.r, g: color.g, b: color.b)
        guard before != after else { return false }
        result[row, column] = after
        let key = row * result.width + column
        if var change = pending[key] { change.after = after; pending[key] = change }
        else { pending[key] = CellChange(row: row, column: column, before: before, after: after) }
        return true
    }

    @discardableResult mutating func fill(_ color: RGBA, row: Int, column: Int, in result: inout PixelResult) -> Bool {
        guard row >= 0, row < result.height, column >= 0, column < result.width else { return false }
        let target = result[row, column]
        let solid = color.a == 0 ? RGBA(r: 0, g: 0, b: 0, a: 0) : RGBA(r: color.r, g: color.g, b: color.b)
        guard target != solid else { return false }
        var stack = [(row, column)]
        while let (r, c) = stack.popLast() {
            guard result[r, c] == target else { continue }
            var left = c, right = c
            while left > 0, result[r, left - 1] == target { left -= 1 }
            while right + 1 < result.width, result[r, right + 1] == target { right += 1 }
            for x in left...right { set(solid, row: r, column: x, in: &result) }
            for neighbor in [r - 1, r + 1] where neighbor >= 0 && neighbor < result.height {
                var inRun = false
                for x in left...right {
                    let matches = result[neighbor, x] == target
                    if matches && !inRun { stack.append((neighbor, x)) }
                    inRun = matches
                }
            }
        }
        return true
    }

    mutating func commit() {
        let changes = pending.values.filter { $0.before != $0.after }
        pending.removeAll()
        guard !changes.isEmpty else { return }
        retainedChanges -= future.reduce(0) { $0 + $1.count }
        future.removeAll()
        past.append(changes); retainedChanges += changes.count
        // Keep the newest operation even when configured below its size.
        while past.count > 1 && (past.count > 100 || retainedBytes > byteLimit) {
            retainedChanges -= past.removeFirst().count
        }
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

    private func validate() throws {
        guard version == 1, settings.isValid, grid.count == settings.height,
              grid.allSatisfy({ $0.count == settings.width && $0.allSatisfy { $0.a == 0 || $0.a == 255 } })
        else { throw PixelError.invalidImage }
    }

    func validatedResult() throws -> PixelResult {
        try validate()
        return PixelResult(width: settings.width, height: settings.height, pixels: grid.flatMap { $0 })
    }

    static func read(from url: URL) throws -> GridDocument {
        let document = try JSONDecoder().decode(GridDocument.self, from: Data(contentsOf: url))
        try document.validate()
        return document
    }

    func write(to url: URL) throws {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
