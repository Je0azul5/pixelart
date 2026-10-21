import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG", jpg = "JPG", pdf = "PDF"
    var id: String { rawValue }
    var type: UTType {
        switch self { case .png: .png; case .jpg: .jpeg; case .pdf: .pdf }
    }
    var ext: String { rawValue.lowercased() }
}

enum ImageExporter {
    static func write(_ result: PixelResult, format: ExportFormat, scale: Int, to url: URL) throws {
        let image = try result.cgImage(scale: scale)
        let data = NSMutableData()
        if format == .pdf {
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil)
            else { throw PixelError.exportFailed }
            context.beginPDFPage(nil)
            context.interpolationQuality = .none
            context.draw(image, in: box)
            context.endPDFPage()
            context.closePDF()
        } else {
            guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil)
            else { throw PixelError.exportFailed }
            var output = image
            if format == .jpg {
                // JPEG has no alpha channel: composite on white explicitly.
                guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                              bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                else { throw PixelError.exportFailed }
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                guard let flattened = context.makeImage() else { throw PixelError.exportFailed }
                output = flattened
            }
            CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw PixelError.exportFailed }
        }
        try (data as Data).write(to: url, options: .atomic)
    }
}
