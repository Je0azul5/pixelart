# Pixelart Studio

Aplicación nativa para macOS que transforma imágenes en pixel art. SwiftUI, procesamiento local y sin dependencias externas.

## Funciones

- Abrir imágenes con `⌘O`, arrastrarlas a la ventana o abrirlas con la app desde Finder.
- Lienzo de **1 a 512 píxeles por lado**, con ancho y alto independientes: 10 × 10, 23 × 49, etc.
- Preajustes de 16, 32, 48 y 64 píxeles.
- Encuadre ajustado con margen transparente, relleno con recorte o estiramiento.
- Paleta de hasta 2–64 colores mediante median cut ponderado. Muestra los colores RGB del resultado ordenados por frecuencia; los niveles de transparencia se conservan por separado.
- Muestreo con promedio de colores o vecino más cercano, y tramado Floyd–Steinberg opcional.
- Comparación con la imagen original y cuadrícula de píxeles.
- Copiar un color HEX o toda la paleta al portapapeles.
- Exportar **PNG, JPG y PDF**, con escala entera de 1× a 32× y un máximo de 8192 píxeles por lado. La ampliación usa vecino más cercano.
- PNG y PDF conservan la transparencia. JPG la compone sobre blanco; su compresión puede alterar ligeramente los colores.

La paleta corresponde al resultado convertido. Las imágenes grandes se reducen a un máximo de 4096 píxeles por lado al importarlas, respetando su orientación. Los archivos animados usan el primer fotograma. El decodificador admite los formatos compatibles con ImageIO en tu versión de macOS, entre ellos PNG, JPEG, HEIC, TIFF, GIF y WebP.

## Requisitos

- macOS 14 Sonoma o posterior.
- Para compilar: Xcode Command Line Tools con Swift 6 o posterior (`xcode-select --install`).

## Ejecutar y probar

```sh
swift run Pixelart
bash scripts/test.sh
```

Las comprobaciones se compilan directamente con Swift y funcionan con Command Line Tools, sin instalar Xcode completo.

## Crear la aplicación

```sh
bash scripts/build-app.sh
open dist/Pixelart.app
```

El script genera `dist/Pixelart.app` y `dist/Pixelart-macOS.zip`, con icono y firma ad hoc local. Puedes copiar la app a Aplicaciones. Compila para la arquitectura del Mac que ejecuta el script (Apple Silicon o Intel).

Para distribuir públicamente con la verificación de Gatekeeper se necesita firmar con Developer ID y notarizar con una cuenta de Apple Developer; el paquete local no está notarizado.

## Organización

- `Sources/Pixelart/PixelEngine.swift`: muestreo, cuantización, tramado y paleta.
- `Sources/Pixelart/ImageExporter.swift`: exportación PNG, JPG y PDF.
- `Sources/Pixelart/AppModel.swift`: importación, tareas cancelables y estado.
- `Sources/Pixelart/ContentView.swift`: interfaz en español y vista previa sin interpolación.
- `Tests/PixelEngineChecks.swift`: dimensiones rectangulares, orientación, paleta, alfa, límites y exportaciones con lectura de vuelta.
- `scripts/` y `packaging/`: creación del paquete `.app`.

No se envían imágenes a servicios externos. Los archivos generados y las compilaciones quedan excluidos de Git.
