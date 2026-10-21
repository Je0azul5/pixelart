import SwiftUI
import UniformTypeIdentifiers

enum Theme {
    static let background = Color(red: 0.065, green: 0.035, blue: 0.115)
    static let panel = Color(red: 0.105, green: 0.065, blue: 0.175)
    static let field = Color(red: 0.17, green: 0.11, blue: 0.26)
    static let accent = Color(red: 0.70, green: 0.43, blue: 1)
    static let secondary = Color(red: 0.68, green: 0.60, blue: 0.80)
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
        .onChange(of: model.settings) { old, _ in model.settingsChanged(from: old) }
        .onChange(of: model.patternOptions) { model.adjustScale() }
        .onChange(of: model.patternMode) { model.adjustScale() }
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
            Text("JeXelart").font(.system(size: 23, weight: .bold, design: .rounded))
            Text("CUADRO A CUADRO").font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2).foregroundStyle(Theme.secondary).padding(.top, 5)
            Spacer()
            Text("Tu imagen. Un cuadro a la vez.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Button(action: model.openImage) { Label("Abrir imagen", systemImage: "plus") }
                .buttonStyle(.bordered).controlSize(.large).padding(.leading, 18)
                .help("Abrir imagen (⌘O)")
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 18)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Convierte en cuadros.").font(.system(size: 18, weight: .semibold))
                        Text("Un color por casilla. Un patrón para crear.")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    section("01", "LIENZO") {
                        HStack(spacing: 10) {
                            dimension("Ancho", value: $model.settings.width)
                            Text("×").foregroundStyle(Theme.secondary).padding(.top, 18)
                            dimension("Alto", value: $model.settings.height)
                        }
                        if !model.settings.isValid {
                            Text("Usa valores de 1 a 512 cuadrados por lado.").font(.caption).foregroundStyle(Theme.accent)
                        }
                        if model.settings.isValid {
                            Text("\(model.settings.width * model.settings.height) cuadrados · columnas × filas")
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
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
                        Toggle("Colores planos", isOn: $model.settings.flatColors).font(.system(size: 12)).padding(.top, 5)
                        if !model.settings.flatColors {
                            Toggle("Promediar colores", isOn: $model.settings.smooth).font(.system(size: 12))
                        }
                        Toggle("Tramado de color", isOn: $model.settings.dither).font(.system(size: 12))
                        Text(model.settings.flatColors ? "Cada cuadro toma el color dominante, sin suavizar los bordes. Desactiva el tramado para bloques limpios." : "El promedio conserva los matices; el tramado crea transiciones con puntos.")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        Toggle("Cuadrícula", isOn: $model.patternOptions.grid).font(.system(size: 12))
                        Toggle("Coordenadas", isOn: $model.patternOptions.coordinates).font(.system(size: 12))
                        ColorPicker("Fondo", selection: Binding(get: {
                            let c = model.patternOptions.background
                            return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
                        }, set: { value in
                            let c = NSColor(value).usingColorSpace(.sRGB) ?? .white
                            model.patternOptions.background = RGBA(r: UInt8(clamping: Int((c.redComponent * 255).rounded())), g: UInt8(clamping: Int((c.greenComponent * 255).rounded())), b: UInt8(clamping: Int((c.blueComponent * 255).rounded())))
                        }), supportsOpacity: false).font(.system(size: 12))
                        Text("La cuadrícula y los números se incluyen al exportar el patrón.")
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }.padding(22)
            }
            divider
            section("03", "EXPORTAR") {
                Picker("Formato", selection: $model.exportFormat) {
                    ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                HStack {
                    Text("Tamaño del cuadro").font(.system(size: 12))
                    Spacer()
                    Picker("Escala", selection: $model.exportScale) {
                        ForEach(model.minScale...model.maxScale, id: \.self) { Text("\($0) px").tag($0) }
                    }.labelsHidden().frame(width: 90)
                }
                Text(model.exportDescription)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
                Button(action: model.export) {
                    Label("Exportar \(model.exportFormat.rawValue)", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canExport)
                Button("Guardar editable…", action: model.saveDocument)
                    .disabled(!model.canExport).frame(maxWidth: .infinity)
                Text(model.patternMode ? "Patrón con fondo, cuadros y coordenadas. PDF conserva las líneas vectoriales." : (model.exportFormat == .jpg ? "JPG usa fondo blanco y compresión con pérdida." : "Imagen sin cuadrícula; conserva las casillas vacías."))
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
        }.background(Theme.panel)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(model.source == nil ? Theme.secondary : Theme.accent).frame(width: 6, height: 6)
                Text(model.source?.name ?? "VISTA PREVIA").font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1)
                Spacer()
                if model.result != nil {
                    Picker("Vista y exportación", selection: $model.patternMode) {
                        Text("Patrón").tag(true)
                        Text("Imagen").tag(false)
                    }.pickerStyle(.segmented).frame(width: 150).labelsHidden()
                    if model.original != nil { Toggle("Original", isOn: $model.showOriginal).toggleStyle(.button) }
                }
            }.foregroundStyle(Theme.secondary).padding(.horizontal, 25).padding(.vertical, 17)
            if model.result != nil {
                HStack(spacing: 10) {
                    Picker("Herramienta", selection: $model.tool) {
                        ForEach(CellTool.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 125)
                    ColorPicker("Color", selection: $model.selectedColor, supportsOpacity: false).labelsHidden()
                    Button(action: model.undo) { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!model.history.canUndo).keyboardShortcut("z", modifiers: .command)
                    Button(action: model.redo) { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!model.history.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
                    Spacer()
                    Text("Zoom").font(.caption)
                    Slider(value: $model.zoom, in: 1...16, step: 0.5).frame(width: 90)
                    Button("Ver completo") { model.zoom = 1 }
                }.disabled(model.busy || model.showOriginal).padding(.horizontal, 24).padding(.bottom, 10)
            }
            GeometryReader { geometry in
                ZStack {
                    DotBackground()
                    if model.showOriginal, let image = model.original {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding(24)
                    } else if let result = model.result {
                        let margin = model.patternMode ? model.patternOptions.margin * 2 : 0
                        let available = min((geometry.size.width - CGFloat(margin) - 32) / CGFloat(result.width),
                                            (geometry.size.height - CGFloat(margin) - 32) / CGFloat(result.height))
                        let cell = max(1, Int(floor(max(1, available) * model.zoom)))
                        let displayScale: CGFloat = model.zoom == 1 ? min(1, max(0.01, available)) : 1
                        ScrollView([.horizontal, .vertical]) {
                            GridCanvas(model: model, result: result, cellSize: cell, displayScale: displayScale, options: model.patternOptions, patternMode: model.patternMode)
                                .frame(width: CGFloat(result.width * cell + margin) * displayScale, height: CGFloat(result.height * cell + margin) * displayScale)
                                .padding(16)
                                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                        }
                    } else if !model.busy {
                        emptyState
                    }
                    if model.busy {
                        HStack(spacing: 9) { ProgressView().controlSize(.small); Text("Creando cuadrados…").font(.caption) }
                            .padding(14).background(.ultraThinMaterial, in: Capsule())
                    }
                }
            }.clipped()
            if let result = model.result {
                HStack {
                    Text(model.showOriginal ? "IMAGEN ORIGINAL" : "\(result.width) × \(result.height) CUADROS · \(model.patternMode ? "PATRÓN" : "IMAGEN")")
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
            Text("De imagen a patrón.").font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("Arrastra tu imagen y conviértela en una cuadrícula de colores.")
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
                Toggle("Símbolos por color", isOn: $model.patternOptions.symbolsEnabled)
                    .font(.system(size: 11))
                    .help("Añade símbolos en la vista Patrón y en sus exportaciones. Ajusta cada color debajo.")
                Button(action: model.copyPalette) { Label("Copiar HEX", systemImage: "doc.on.doc") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .disabled(model.result == nil || model.busy)
            }
            if let result = model.result, !result.palette.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(result.palette) { entry in
                            paletteEntry(entry)
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

    private func paletteEntry(_ entry: PaletteColor) -> some View {
        let visible = !model.patternOptions.hiddenSymbolColors.contains(entry.color)
        return VStack(alignment: .leading, spacing: 6) {
            Button { model.select(entry.color); model.copy(entry.color.hex); model.message = "\(entry.color.hex) seleccionado y copiado" } label: {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(red: Double(entry.color.r) / 255, green: Double(entry.color.g) / 255, blue: Double(entry.color.b) / 255))
                        .frame(width: 78, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.12)))
                        .overlay {
                            if model.patternOptions.symbolsEnabled && visible {
                                Text(model.symbol(for: entry.color)).font(.system(size: 24, design: .monospaced))
                                    .foregroundStyle(PatternOptions.usesLightInk(for: entry.color) ? Color.white : Color.black)
                            }
                        }
                    Text(entry.color.hex).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary)
                }
            }.buttonStyle(.plain).help("Seleccionar y copiar \(entry.color.hex)")
            Text("\(entry.count) cuadros").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.secondary)
            Button("Reemplazar") { model.replaceColor(entry.color) }
                .buttonStyle(.plain).font(.system(size: 9)).help("Cambiar todas las celdas de este color por el color de dibujo")
            if model.patternOptions.symbolsEnabled {
                Toggle("Activar", isOn: Binding(get: { visible }, set: { model.setSymbolVisible($0, for: entry.color) }))
                    .font(.system(size: 10)).accessibilityLabel("Activar símbolo para \(entry.color.hex)")
                Picker("Símbolo para \(entry.color.hex)", selection: Binding(
                    get: { model.symbol(for: entry.color) }, set: { model.setSymbol($0, for: entry.color) }
                )) {
                    ForEach(PatternOptions.symbols, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 78).disabled(!visible)
            }
        }.frame(width: 78).disabled(model.busy)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield").font(.system(size: 10))
            Text("100 % local. Tus imágenes se quedan en tu Mac.")
            Spacer()
            Text(model.message ?? "JEXELART · CADA CUADRO CUENTA")
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
                .accessibilityLabel("\(title) en cuadrados")
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
    private let cells = [0, 3, 5, 6, 9, 10, 12, 15]
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
