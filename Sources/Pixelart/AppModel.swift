import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    var settings = PixelSettings()
    var source: SourceImage?
    var result: PixelResult?
    var preview: NSImage?
    var patternPreview: NSImage?
    var original: NSImage?
    var busy = false
    var error: String?
    var message: String?
    var exportFormat = ExportFormat.png
    var exportScale = 16
    var patternMode = true
    var patternOptions = PatternOptions()
    var showOriginal = false
    private var work: Task<Void, Never>?
    private var generation = UUID()

    var canExport: Bool { result != nil && !busy && settings.isValid }
    var minScale: Int { patternMode ? 8 : 1 }
    var maxScale: Int {
        let border = patternMode ? patternOptions.margin * 2 : 0
        return max(minScale, min(32, (8192 - border) / max(settings.width, settings.height, 1)))
    }
    var displayedPreview: NSImage? { showOriginal ? original : (patternMode ? patternPreview : preview) }
    var exportDescription: String {
        guard settings.isValid else { return "Introduce dimensiones válidas" }
        let border = patternMode ? patternOptions.margin * 2 : 0
        return "\(settings.width * exportScale + border) × \(settings.height * exportScale + border) px"
    }

    func adjustScale() { exportScale = min(max(exportScale, minScale), maxScale) }

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Abrir imagen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    func load(_ url: URL) {
        work?.cancel()
        let token = UUID(); generation = token
        busy = true; message = nil
        work = Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) { try PixelEngine.load(url: url) }.value
                guard generation == token, !Task.isCancelled else { return }
                source = loaded
                original = NSImage(cgImage: loaded.image, size: NSSize(width: loaded.image.width, height: loaded.image.height))
                result = nil; preview = nil; patternPreview = nil
                settings.width = min(512, max(1, settings.width))
                settings.height = min(512, max(1, Int((Double(settings.width) * Double(loaded.image.height) / Double(loaded.image.width)).rounded())))
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
        guard let source, settings.isValid else { busy = false; return }
        let options = settings
        let pattern = patternOptions
        busy = true; message = nil
        adjustScale()
        work = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                let task = Task.detached(priority: .userInitiated) {
                    let converted = try PixelEngine.render(source: source.image, settings: options)
                    let scale = max(2, min(20, 2048 / max(converted.width, converted.height)))
                    let patternImage = try PatternRenderer.image(converted, cellSize: scale, options: pattern)
                    return (converted, SourceImage(image: patternImage, name: "patrón"))
                }
                let (converted, sheet) = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                guard generation == token, !Task.isCancelled else { return }
                let cg = try converted.cgImage()
                result = converted
                preview = NSImage(cgImage: cg, size: NSSize(width: converted.width, height: converted.height))
                patternPreview = NSImage(cgImage: sheet.image, size: NSSize(width: sheet.image.width, height: sheet.image.height))
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
        copy(result.palette.map(\.color.hex).joined(separator: "\n"))
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
