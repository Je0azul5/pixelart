import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    var settings = PixelSettings()
    var source: SourceImage?
    var result: PixelResult?
    var original: NSImage?
    var busy = false
    var error: String?
    var message: String?
    var exportFormat = ExportFormat.png
    var exportScale = 16
    var patternMode = true
    var patternOptions = PatternOptions()
    var showOriginal = false
    var tool = CellTool.pencil
    var selectedColor = Color.black
    var zoom = 1.0
    var history = GridHistory()
    private var restoredSettings: PixelSettings?

    var paintColor: RGBA {
        let color = NSColor(selectedColor).usingColorSpace(.sRGB) ?? .black
        return RGBA(r: UInt8(clamping: Int((color.redComponent * 255).rounded())), g: UInt8(clamping: Int((color.greenComponent * 255).rounded())), b: UInt8(clamping: Int((color.blueComponent * 255).rounded())))
    }

    func settingsChanged(from old: PixelSettings) {
        if settings == restoredSettings { restoredSettings = nil; return }
        restoredSettings = nil
        if old.width == settings.width, old.height == settings.height,
           old.fit == settings.fit, old.flatColors == settings.flatColors,
           old.smooth == settings.smooth, old.dither == settings.dither,
           let result, settings.isValid, !busy, result.width == settings.width, result.height == settings.height {
            let reduced = PixelEngine.reduce(result, limit: settings.colorCount)
            replaceResult(reduced)
        } else { render() }
    }

    private func replaceResult(_ new: PixelResult) {
        guard var current = result, current.width == new.width, current.height == new.height else { return }
        for row in 0..<current.height {
            for column in 0..<current.width { history.set(new[row, column], row: row, column: column, in: &current) }
        }
        result = current
        history.commit()
    }

    func select(_ color: RGBA) {
        selectedColor = Color(red: Double(color.r) / 255, green: Double(color.g) / 255, blue: Double(color.b) / 255)
    }

    func edit(row: Int, column: Int, initial: Bool) {
        guard !busy, settings.isValid, !showOriginal, var current = result,
              row >= 0, row < current.height, column >= 0, column < current.width else { return }
        switch tool {
        case .eyedropper:
            if initial {
                let color = current[row, column]
                if color.a > 0 { select(color); message = color.hex }
                else { message = "Casilla vacía" }
            }
        case .pencil: history.set(paintColor, row: row, column: column, in: &current)
        case .eraser: history.set(RGBA(r: 0, g: 0, b: 0, a: 0), row: row, column: column, in: &current)
        case .fill:
            if initial { history.fill(paintColor, row: row, column: column, in: &current) }
        }
        result = current
    }

    func endStroke() { history.commit() }
    func undo() {
        guard !busy, var current = result else { return }
        history.undo(in: &current); result = current
    }
    func redo() {
        guard !busy, var current = result else { return }
        history.redo(in: &current); result = current
    }
    func replaceColor(_ color: RGBA) {
        guard !busy, var current = result else { return }
        for row in 0..<current.height {
            for column in 0..<current.width where current[row, column] == color {
                history.set(paintColor, row: row, column: column, in: &current)
            }
        }
        result = current; history.commit()
    }

    func saveDocument() {
        guard canExport, let result else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jexelartPattern]
        panel.nameFieldStringValue = "\(source?.name ?? "patron").jexelart"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try GridDocument(settings: settings, grid: result.grid, options: patternOptions).write(to: url)
            message = "Patrón editable guardado"
        } catch { self.error = error.localizedDescription }
    }
    private var work: Task<Void, Never>?
    private var generation = UUID()

    var canExport: Bool { result?.width == settings.width && result?.height == settings.height && !busy && settings.isValid }
    var minScale: Int { patternMode ? 8 : 1 }
    var maxScale: Int {
        let border = patternMode ? patternOptions.margin * 2 : 0
        return max(minScale, min(32, (8192 - border) / max(settings.width, settings.height, 1)))
    }
    var exportDescription: String {
        guard settings.isValid else { return "Introduce dimensiones válidas" }
        let border = patternMode ? patternOptions.margin * 2 : 0
        return "\(settings.width * exportScale + border) × \(settings.height * exportScale + border) px"
    }

    func adjustScale() { exportScale = min(max(exportScale, minScale), maxScale) }

    func symbol(for color: RGBA) -> String {
        patternOptions.resolvedSymbols(for: result?.palette ?? [])[color] ?? PatternOptions.symbols[0]
    }

    func setSymbol(_ symbol: String, for color: RGBA) {
        guard PatternOptions.symbols.contains(symbol), let result else { return }
        var assignments = patternOptions.resolvedSymbols(for: result.palette)
        let old = assignments[color]
        if let other = assignments.first(where: { $0.key != color && $0.value == symbol })?.key {
            assignments[other] = old
        }
        assignments[color] = symbol
        patternOptions.symbolAssignments = assignments
    }

    func setSymbolVisible(_ visible: Bool, for color: RGBA) {
        if visible { patternOptions.hiddenSymbolColors.remove(color) }
        else { patternOptions.hiddenSymbolColors.insert(color) }
    }

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .json, .jexelartPattern]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Abrir imagen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    func load(_ url: URL) {
        if ["jexelart", "json"].contains(url.pathExtension.lowercased()) {
            do {
                let document = try GridDocument.read(from: url)
                let restored = try document.validatedResult()
                work?.cancel(); generation = UUID(); busy = false
                source = nil; original = nil; showOriginal = false
                restoredSettings = settings == document.settings ? nil : document.settings
                settings = document.settings; patternOptions = document.options
                result = restored; history = GridHistory(); zoom = 1
                adjustScale(); message = "Patrón editable abierto"
            } catch { self.error = error.localizedDescription }
            return
        }
        work?.cancel()
        let token = UUID(); generation = token
        busy = true; message = nil
        work = Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) { try PixelEngine.load(url: url) }.value
                guard generation == token, !Task.isCancelled else { return }
                source = loaded
                original = NSImage(cgImage: loaded.image, size: NSSize(width: loaded.image.width, height: loaded.image.height))
                result = nil
                history = GridHistory(); zoom = 1
                render()
            } catch {
                guard generation == token else { return }
                busy = false; self.error = error.localizedDescription
            }
        }
    }

    func render() {
        work?.cancel()
        let token = UUID(); generation = token
        guard settings.isValid else { busy = false; return }
        let input: CGImage
        if let source { input = source.image }
        else if let result, let image = try? result.cgImage() { input = image }
        else { busy = false; return }
        let options = settings
        busy = true; message = nil
        adjustScale()
        work = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                let task = Task.detached(priority: .userInitiated) {
                    try PixelEngine.render(source: input, settings: options)
                }
                let converted = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                guard generation == token, !Task.isCancelled else { return }
                result = converted
                history = GridHistory()
                busy = false
            } catch is CancellationError {
                // A newer edit owns the preview now.
            } catch {
                guard generation == token else { return }
                busy = false; self.error = error.localizedDescription
            }
        }
    }

    func export() {
        guard canExport, let result else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportFormat.type]
        panel.nameFieldStringValue = "\(source?.name ?? "imagen")-jexelart-\(patternMode ? "patron" : "imagen")-\(result.width)x\(result.height).\(exportFormat.ext)"
        panel.canCreateDirectories = true
        panel.prompt = "Exportar"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ImageExporter.write(result, format: exportFormat, scale: exportScale, to: url,
                                    pattern: patternMode ? patternOptions : nil)
            message = "Guardado: \(url.lastPathComponent)"
        } catch { self.error = error.localizedDescription }
    }

    func copyPalette() {
        guard let result else { return }
        let symbols = patternOptions.resolvedSymbols(for: result.palette)
        copy(result.palette.map { entry in
            if patternOptions.symbolsEnabled, !patternOptions.hiddenSymbolColors.contains(entry.color), let symbol = symbols[entry.color] {
                return "\(entry.color.hex)  \(symbol)"
            }
            return entry.color.hex
        }.joined(separator: "\n"))
        message = "Paleta copiada al portapapeles"
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in self.load(url) }
        }
        return true
    }
}
