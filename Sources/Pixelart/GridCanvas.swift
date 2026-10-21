import AppKit
import SwiftUI

struct GridCanvas: NSViewRepresentable {
    let model: AppModel
    let result: PixelResult
    let resultVersion: UInt64
    let cellSize: Int
    let displayScale: CGFloat
    let options: PatternOptions
    let patternMode: Bool

    func makeNSView(context: Context) -> CellCanvasView { CellCanvasView() }
    func updateNSView(_ view: CellCanvasView, context: Context) {
        guard view.result == nil || view.resultVersion != resultVersion || view.cellSize != cellSize
                || view.options != options || view.patternMode != patternMode || view.displayScale != displayScale else { return }
        view.model = model; view.result = result; view.cellSize = cellSize
        view.resultVersion = resultVersion
        view.options = options; view.patternMode = patternMode; view.displayScale = displayScale
        view.needsDisplay = true
    }
}

final class CellCanvasView: NSView {
    var model: AppModel?
    var result: PixelResult?
    var resultVersion: UInt64 = 0
    var cellSize = 16
    var displayScale: CGFloat = 1
    var options = PatternOptions()
    var patternMode = true
    private var lastCell: (row: Int, column: Int)?

    override func draw(_ dirtyRect: NSRect) {
        guard let result, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: dirtyRect)
        context.scaleBy(x: displayScale, y: displayScale)
        if patternMode {
            PatternRenderer.draw(result, in: context, cellSize: cellSize, options: options)
        } else {
            var plain = options
            plain.grid = false; plain.coordinates = false; plain.symbolsEnabled = false
            context.translateBy(x: -CGFloat(plain.margin), y: -CGFloat(plain.margin))
            PatternRenderer.draw(result, in: context, cellSize: cellSize, options: plain)
        }
    }

    private func cell(at event: NSEvent) -> (row: Int, column: Int)? {
        guard let result else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let margin = CGFloat(patternMode ? options.margin : 0)
        let sheetHeight = CGFloat(result.height * cellSize) + margin * 2
        guard let address = GridGeometry.cell(at: CGPoint(x: point.x / displayScale, y: sheetHeight - point.y / displayScale),
                                             width: result.width, height: result.height, cellSize: CGFloat(cellSize), margin: margin) else { return nil }
        return (address.row, address.column)
    }

    override func mouseDown(with event: NSEvent) {
        model?.endStroke()
        lastCell = cell(at: event)
        if let lastCell { model?.edit(row: lastCell.row, column: lastCell.column, initial: true) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let next = cell(at: event) else { lastCell = nil; return }
        defer { lastCell = next }
        guard model?.tool == .pencil || model?.tool == .eraser else { return }
        // Interpolate cell indices so fast drags leave a continuous chain of whole squares.
        var x = lastCell?.column ?? next.column, y = lastCell?.row ?? next.row
        let dx = abs(next.column - x), dy = -abs(next.row - y)
        let sx = x < next.column ? 1 : -1, sy = y < next.row ? 1 : -1
        var error = dx + dy
        var cells: [CellAddress] = []
        cells.reserveCapacity(max(dx, -dy) + 1)
        while true {
            cells.append(CellAddress(row: y, column: x))
            if x == next.column && y == next.row { break }
            let doubled = 2 * error
            if doubled >= dy { error += dy; x += sx }
            if doubled <= dx { error += dx; y += sy }
        }
        model?.edit(cells: cells, initial: false)
    }

    override func mouseUp(with event: NSEvent) {
        model?.endStroke(); lastCell = nil
    }
}
