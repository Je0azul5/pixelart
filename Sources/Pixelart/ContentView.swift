import SwiftUI
import UniformTypeIdentifiers

enum Theme {
    static let background = Color(red: 0.070, green: 0.078, blue: 0.090)
    static let panel = Color(red: 0.100, green: 0.110, blue: 0.125)
    static let field = Color(red: 0.145, green: 0.155, blue: 0.175)
    static let accent = Color(red: 1, green: 0.43, blue: 0.27)
    static let secondary = Color(red: 0.58, green: 0.62, blue: 0.67)
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            HStack(spacing: 0) {
                controls.frame(width: 270)
                Rectangle().fill(.white.opacity(0.07)).frame(width: 1)
                workspace
            }
            footer
        }
        .background(Theme.background)
        .onChange(of: model.settings) { model.render() }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: model.drop)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .padding(8).allowsHitTesting(false)
            }
        }
        .alert("No se pudo completar la acción", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Aceptar") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PixelMark().frame(width: 30, height: 30)
            Text("pixelart").font(.system(size: 23, weight: .bold, design: .rounded))
            Text("STUDIO").font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2).foregroundStyle(Theme.secondary).padding(.top, 5)
            Spacer()
            Text("De imagen a pequeños mundos.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Button(action: model.openImage) { Label("Abrir imagen", systemImage: "plus") }
                .buttonStyle(.bordered).controlSize(.large).padding(.leading, 18)
                .help("Abrir imagen (⌘O)")
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 18)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Tu imagen, píxel a píxel.").font(.system(size: 18, weight: .semibold))
                    Text("Ajusta los detalles. Encuentra tu estilo.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                section("01", "LIENZO") {
                    HStack(spacing: 10) {
                        dimension("Ancho", value: $model.settings.width)
                        Text("×").foregroundStyle(Theme.secondary).padding(.top, 18)
                        dimension("Alto", value: $model.settings.height)
                    }
                    if !model.settings.isValid {
                        Text("Usa valores de 1 a 512 px por lado.").font(.caption).foregroundStyle(Theme.accent)
                    }
                    HStack(spacing: 6) {
                        ForEach([16, 32, 48, 64], id: \.self) { size in
                            Button("\(size)²") { model.settings.width = size; model.settings.height = size }
                                .buttonStyle(.plain).font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(model.settings.width == size && model.settings.height == size ? Theme.accent.opacity(0.18) : Theme.field)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    Picker("Encuadre", selection: $model.settings.fit) {
                        ForEach(ImageFit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Text(fitHint).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                divider
                section("02", "COLOR Y ESTILO") {
                    HStack {
                        Text("Máximo de colores").font(.system(size: 12))
                        Spacer()
                        Text("\(model.settings.colorCount)").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.accent)
                    }
                    Slider(value: Binding(get: { Double(model.settings.colorCount) }, set: { model.settings.colorCount = Int($0) }), in: 2...64, step: 1)
                    HStack { Text("2 · RETRO"); Spacer(); Text("64 · DETALLE") }
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary)
                    Toggle("Promediar colores", isOn: $model.settings.smooth).font(.system(size: 12)).padding(.top, 5)
                    Toggle("Tramado de color", isOn: $model.settings.dither).font(.system(size: 12))
                    Text("El tramado mezcla puntos para crear transiciones de color.")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                divider
                section("03", "EXPORTAR") {
                    Picker("Formato", selection: $model.exportFormat) {
                        ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    HStack {
                        Text("Escala").font(.system(size: 12))
                        Spacer()
                        Picker("Escala", selection: $model.exportScale) {
                            ForEach(1...model.maxScale, id: \.self) { Text("\($0)×").tag($0) }
                        }.labelsHidden().frame(width: 90)
                    }
                    Text(model.settings.isValid ? "\(model.settings.width * model.exportScale) × \(model.settings.height * model.exportScale) px · bordes nítidos" : "Introduce dimensiones válidas")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
                    Button(action: model.export) {
                        Label("Exportar \(model.exportFormat.rawValue)", systemImage: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canExport)
                    Text(model.exportFormat == .jpg ? "JPG usa fondo blanco y compresión con pérdida." : "Conserva la transparencia de la imagen.")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(22)
        }.background(Theme.panel)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(model.source == nil ? Theme.secondary : Theme.accent).frame(width: 6, height: 6)
                Text(model.source?.name ?? "VISTA PREVIA").font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1)
                Spacer()
                if model.source != nil {
                    Toggle("Original", isOn: $model.showOriginal).toggleStyle(.button)
                    Toggle(isOn: $model.showGrid) { Image(systemName: "grid") }.toggleStyle(.button).help("Mostrar cuadrícula")
                }
            }.foregroundStyle(Theme.secondary).padding(.horizontal, 25).padding(.vertical, 17)
            GeometryReader { geometry in
                ZStack {
                    DotBackground()
                    if let image = model.showOriginal ? model.original : model.preview {
                        let ratio = model.showOriginal ? image.size.width / image.size.height : CGFloat(model.result?.width ?? 1) / CGFloat(model.result?.height ?? 1)
                        let size = fittedSize(ratio: ratio, bounds: geometry.size)
                        ZStack {
                            Checkerboard()
                            Image(nsImage: image).interpolation(model.showOriginal ? .high : .none).resizable().aspectRatio(contentMode: .fit)
                            if model.showGrid && !model.showOriginal, let result = model.result {
                                PixelGrid(columns: result.width, rows: result.height)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                        .overlay(Rectangle().stroke(.white.opacity(0.16), lineWidth: 1))
                        .shadow(color: .black.opacity(0.25), radius: 25, y: 10)
                    } else if !model.busy {
                        emptyState
                    }
                    if model.busy {
                        HStack(spacing: 9) { ProgressView().controlSize(.small); Text("Creando píxeles…").font(.caption) }
                            .padding(14).background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }.clipped()
            if let result = model.result {
                HStack {
                    Text(model.showOriginal ? "IMAGEN ORIGINAL" : "\(result.width) × \(result.height) PÍXELES")
                    Spacer()
                    Text("\(result.palette.count) COLORES")
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 26).padding(.vertical, 14)
            }
            palette
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            PixelMark().frame(width: 70, height: 70).padding(.bottom, 8)
            Text("Todo empieza con una imagen.").font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("Arrastra un archivo aquí y dale una nueva resolución.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            Button("Elegir imagen", action: model.openImage).buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 5)
            Text("PNG · JPG · HEIC · TIFF · GIF · WEBP").font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(Theme.secondary)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PALETA DE LA IMAGEN").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                Spacer()
                Button(action: model.copyPalette) { Label("Copiar HEX", systemImage: "doc.on.doc") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .disabled(model.result == nil || model.busy)
            }
            if let result = model.result, !result.palette.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(result.palette) { entry in
                            Button { model.copy(entry.color.hex); model.message = "\(entry.color.hex) copiado" } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 5).fill(Color(red: Double(entry.color.r) / 255, green: Double(entry.color.g) / 255, blue: Double(entry.color.b) / 255))
                                        .frame(width: 66, height: 40).overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.12)))
                                    Text(entry.color.hex).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary)
                                }
                            }.buttonStyle(.plain).help("Copiar \(entry.color.hex) · \(entry.count) píxeles")
                        }
                    }.padding(.bottom, 4)
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<8) { i in RoundedRectangle(cornerRadius: 5).fill(Theme.field.opacity(1 - Double(i) * 0.08)).frame(height: 40) }
                }
                Text(model.result == nil ? "Los colores de tu creación aparecerán aquí." : "La imagen es completamente transparente.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }.padding(24).background(Theme.panel)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield").font(.system(size: 10))
            Text("100 % local. Tus imágenes se quedan en tu Mac.")
            Spacer()
            Text(model.message ?? "HECHO DE PEQUEÑOS DETALLES")
                .lineLimit(1).foregroundStyle(model.message == nil ? Theme.secondary : Theme.accent)
        }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 22).padding(.vertical, 11)
    }

    private var divider: some View { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }

    private var fitHint: String {
        switch model.settings.fit {
        case .fit: "Conserva la proporción; añade margen transparente."
        case .fill: "Llena el lienzo recortando los bordes."
        case .stretch: "Adapta la imagen al ancho y alto exactos."
        }
    }

    private func dimension(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            TextField(title, value: value, format: .number.grouping(.never))
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .textFieldStyle(.plain).padding(10).background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("\(title) en píxeles")
        }
    }

    private func section<Content: View>(_ number: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Text(number).foregroundStyle(Theme.accent)
                Text(title).tracking(1.2)
            }.font(.system(size: 10, weight: .semibold, design: .monospaced)).padding(.bottom, 2)
            content()
        }
    }

    private func fittedSize(ratio: CGFloat, bounds: CGSize) -> CGSize {
        let w = max(1, bounds.width - 72), h = max(1, bounds.height - 56)
        return ratio > w / h ? CGSize(width: w, height: w / ratio) : CGSize(width: h * ratio, height: h)
    }
}

struct PixelMark: View {
    private let cells = [0, 1, 2, 4, 6, 8, 9, 10, 12]
    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / 4
            ForEach(cells, id: \.self) { i in
                Rectangle().fill(Theme.accent.opacity(i == 12 ? 0.4 : 1))
                    .frame(width: unit - 2, height: unit - 2)
                    .offset(x: CGFloat(i % 4) * unit, y: CGFloat(i / 4) * unit)
            }
        }.accessibilityHidden(true)
    }
}

struct DotBackground: View {
    var body: some View {
        Canvas { context, size in
            for x in stride(from: 12.0, to: size.width, by: 20) {
                for y in stride(from: 12.0, to: size.height, by: 20) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.08)))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.20)))
            for row in 0...Int(size.height / 12) {
                for col in 0...Int(size.width / 12) where (row + col).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: col * 12, y: row * 12, width: 12, height: 12)), with: .color(Color(white: 0.24)))
                }
            }
        }.clipped().accessibilityHidden(true)
    }
}

struct PixelGrid: View {
    let columns: Int
    let rows: Int
    var body: some View {
        Canvas { context, size in
            guard size.width / CGFloat(columns) >= 4, size.height / CGFloat(rows) >= 4 else { return }
            var path = Path()
            for x in 0...columns {
                let px = CGFloat(x) * size.width / CGFloat(columns)
                path.move(to: CGPoint(x: px, y: 0)); path.addLine(to: CGPoint(x: px, y: size.height))
            }
            for y in 0...rows {
                let py = CGFloat(y) * size.height / CGFloat(rows)
                path.move(to: CGPoint(x: 0, y: py)); path.addLine(to: CGPoint(x: size.width, y: py))
            }
            context.stroke(path, with: .color(.black.opacity(0.22)), lineWidth: 0.5)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
