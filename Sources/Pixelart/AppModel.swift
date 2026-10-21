import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    var settings = PixelSettings()
    var source: SourceImage?
    var result: PixelResult?
    var preview: NSImage?
    var original: NSImage?
    var busy = false
    var error: String?
    var message: String?
    var exportFormat = ExportFormat.png
    var exportScale = 10
    var showGrid = false
    var showOriginal = false
    private var work: Task<Void, Never>?
    private var generation = UUID()

    var canExport: Bool { result != nil && !busy && settings.isValid }
    var maxScale: Int { max(1, min(32, 8192 / max(settings.width, settings.height, 1))) }

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
                result = nil; preview = nil
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
        busy = true; message = nil
        exportScale = min(exportScale, maxScale)
        work = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                let task = Task.detached(priority: .userInitiated) { try PixelEngine.render(source: source.image, settings: options) }
                let converted = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                guard generation == token, !Task.isCancelled else { return }
                let cg = try converted.cgImage()
                result = converted
                preview = NSImage(cgImage: cg, size: NSSize(width: converted.width, height: converted.height))
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
        panel.nameFieldStringValue = "\(source?.name ?? "imagen")-pixelart-\(result.width)x\(result.height).\(exportFormat.ext)"
        panel.canCreateDirectories = true
        panel.prompt = "Exportar"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ImageExporter.write(result, format: exportFormat, scale: exportScale, to: url)
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
