# JeXelart

App nativa para macOS para convertir ilustraciones y fotos en patrones de **cuadros de colores**, con interfaz morada oscura. Todo se procesa localmente.

## De imagen a patrón

1. Abre una imagen con `⌘O` o arrástrala a la ventana.
2. Elige las columnas y filas del lienzo, por ejemplo **10 × 10**, **23 × 49** o **48 × 48**. Cada casilla representa exactamente un píxel de la imagen convertida.
3. Ajusta el máximo de colores. **Colores planos**, activado inicialmente, toma el color dominante de cada casilla, agrupa tonos casi idénticos y elimina la transparencia parcial para formar bloques definidos. Puedes desactivarlo para conservar matices y transparencia parcial.
4. La vista **Patrón** muestra cuadros sobre blanco, cuadrícula y coordenadas de filas y columnas, como una guía para reproducir la ilustración. Los cuadros siempre son cuadrados, aunque el lienzo sea rectangular.
5. Exporta en **PNG, JPG o PDF**. El patrón incluye los márgenes, las líneas y los números visibles. PDF dibuja las casillas y la cuadrícula como vectores.

Puedes ocultar la cuadrícula y las coordenadas por separado. La vista **Imagen** exporta solo los píxeles, sin papel ni coordenadas. **Original** sirve para comparar y no modifica qué se exporta.

La paleta muestra los colores RGB del resultado, ordenados por frecuencia. Haz clic en un color para copiar su HEX o usa **Copiar HEX** para copiar toda la paleta.

## Opciones

- Lienzos de **1 a 512 cuadros por lado**, con ancho y alto independientes.
- Preajustes de 16, 32, 48 y 64 cuadros.
- Encuadre ajustado con margen transparente, relleno con recorte o estiramiento.
- Máximo de 2–64 colores mediante median cut ponderado.
- Color dominante por casilla, muestreo con promedio o vecino más cercano y tramado Floyd–Steinberg opcional.
- Patrón exportable con cuadros de 8–32 px; imagen sin cuadrícula a escala de 1× a 32×. Máximo de 8192 px por lado, incluidos los márgenes del patrón.
- PNG y PDF en modo Imagen conservan la transparencia. El patrón usa fondo blanco. JPG siempre usa fondo blanco y compresión con pérdida.

Las imágenes grandes se reducen a un máximo de 4096 píxeles por lado al importarlas, respetando su orientación. Los archivos animados usan el primer fotograma. Admite los formatos compatibles con ImageIO en tu versión de macOS, entre ellos PNG, JPEG, HEIC, TIFF, GIF y WebP.

## Ejecutar, comprobar y empaquetar

Requiere macOS 14 Sonoma o posterior. Para compilar, instala Command Line Tools con Swift 6 o posterior (`xcode-select --install`). No necesita dependencias externas ni Xcode completo.

```sh
swift run JeXelart
bash scripts/test.sh
bash scripts/build-app.sh
open dist/JeXelart.app
```

El script genera **`dist/JeXelart.app`** y **`dist/JeXelart-macOS.zip`**, con icono morado y firma ad hoc local. Puedes copiar la app a Aplicaciones. Compila para la arquitectura del Mac que ejecuta el script (Apple Silicon o Intel).

Para distribuir públicamente con la verificación de Gatekeeper se necesita firmar con Developer ID y notarizar con una cuenta de Apple Developer; el paquete local no está notarizado.

También puedes generar un ejemplo de patrón en los tres formatos usando un archivo local, sin incorporarlo al repositorio:

```sh
bash scripts/test.sh /ruta/a/imagen.png dist/examples
```

## Código

- `Sources/Pixelart/PixelEngine.swift`: muestreo por casillas, cuantización, tramado y paleta.
- `Sources/Pixelart/PatternRenderer.swift`: cuadros, fondo blanco, cuadrícula y coordenadas compartidos entre vista previa y exportación.
- `Sources/Pixelart/ImageExporter.swift`: PNG, JPG y PDF vectorial.
- `Sources/Pixelart/AppModel.swift`: importación, tareas cancelables y estado.
- `Sources/Pixelart/ContentView.swift`: interfaz JeXelart en español.
- `Tests/PixelEngineChecks.swift`: dimensiones, orientación, paleta, alfa, color dominante, coordenadas y exportaciones con lectura de vuelta.
- `scripts/` y `packaging/`: creación del paquete `.app`.

Las compilaciones, ejemplos e imágenes generadas quedan excluidos de Git.
