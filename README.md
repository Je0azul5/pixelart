# JeXelart

App nativa para macOS para convertir ilustraciones y fotos en patrones de **cuadros de colores**, con interfaz morada oscura. Todo se procesa localmente.

## De imagen a patrón

1. Abre una imagen con `⌘O` o arrástrala a la ventana.
2. Elige las columnas y filas del lienzo, por ejemplo **10 × 10**, **23 × 49** o **48 × 48**. El ancho cuenta columnas y el alto cuenta filas. **25 × 25 = 625 cuadrados** y **30 × 50 = 1.500**. Abrir una imagen conserva ambas dimensiones.
3. Ajusta el máximo de colores. **Colores planos**, activado inicialmente, toma el color dominante de cada casilla, agrupa tonos casi idénticos y elimina la transparencia parcial para formar bloques definidos. Puedes desactivarlo para usar promedio o vecino más cercano al elegir el color representativo. En todos los modos, cada casilla queda vacía o contiene un único color opaco.
4. La vista **Patrón** muestra cuadros sobre blanco, cuadrícula y coordenadas de filas y columnas, como una guía para reproducir la ilustración. Los cuadros siempre son cuadrados, aunque el lienzo sea rectangular.
5. Exporta en **PNG, JPG o PDF**. El patrón incluye el fondo, los márgenes, las líneas y los números visibles. PNG conserva colores exactos; JPG mantiene su compresión con pérdida. PDF dibuja las casillas y la cuadrícula como vectores.

Puedes ocultar la cuadrícula y las coordenadas por separado. La vista **Imagen** exporta solo los píxeles, sin papel ni coordenadas. **Original** sirve para comparar y no modifica qué se exporta.

La paleta muestra cada color RGB, su HEX y el número de cuadrados que lo utilizan, ordenados por frecuencia. Haz clic para seleccionar un color de dibujo y copiar su HEX, o usa **Copiar HEX** para copiar toda la paleta. **Reemplazar** cambia todas las celdas de ese color por el color de dibujo actual.

## Edición por cuadrados

La matriz `grid[fila][columna]` es el documento de trabajo; la vista dibuja directamente rectángulos rellenos y luego superpone la cuadrícula, las coordenadas y los símbolos opcionales. No se usa una imagen pixelada como lienzo de edición.

- **Lápiz:** pinta casillas enteras; un arrastre rápido conecta las casillas recorridas.
- **Borrador:** deja vacía la casilla seleccionada.
- **Cuentagotas:** selecciona el RGB exacto de una casilla; identifica las vacías sin asignarles un color.
- **Bote:** rellena las casillas del mismo color conectadas por sus lados.
- **Color:** elige cualquier color sólido, sin transparencia parcial.
- **Deshacer / Rehacer:** botones o `⌘Z` / `⇧⌘Z`. Cada trazo, relleno o reemplazo es una acción; se conservan hasta 100 acciones mediante cambios por celda.

El zoom cambia solo el tamaño visual de los cuadrados. Usa las barras de desplazamiento para recorrer el patrón ampliado y **Ver completo** para ajustarlo al espacio disponible. Cuadrícula, coordenadas, símbolos, fondo y zoom conservan las ediciones. Reducir el máximo de colores actúa sobre la matriz editada y se puede deshacer. Cambiar dimensiones o parámetros de conversión regenera el patrón desde la imagen original (o desde la matriz si abriste un editable) y comienza un historial nuevo.

## Guardar y abrir un patrón editable

**Guardar editable…** crea un archivo `.jexelart` en JSON con la matriz de colores, dimensiones, configuración, fondo y símbolos. Ábrelo con **Abrir imagen**, `⌘O` o arrastrándolo a la ventana para seguir editando, sin volver a cuantizar sus colores. Las celdas vacías conservan alfa 0; las coloreadas usan alfa 255. El historial de deshacer corresponde a la sesión y no se guarda en el archivo.

Para **PNG con cuadrícula**, usa la vista Patrón y activa Cuadrícula. Para **PNG sin cuadrícula**, desactívala (conserva el papel y las coordenadas si están activadas) o selecciona Imagen (solo las celdas). Activa Coordenadas para exportar un patrón numerado; al aumentar el tamaño del cuadro solo aumenta la resolución del archivo, sin añadir filas ni columnas.

## Símbolos por color

Activa **Símbolos por color** en la cabecera de la paleta para colocar un símbolo en cada cuadro del patrón, como en una guía de bordado. Cada color recibe un símbolo diferente entre 64 opciones: cruces, círculos, cuadrados, estrellas, corazones, letras y números.

Debajo de cada color puedes **activar o desactivar** su símbolo y elegir otro en el desplegable. Si eliges uno que ya utiliza otro color, los dos se intercambian para mantener la correspondencia. Los símbolos se dibujan blancos o negros según el contraste del fondo; las casillas transparentes se dejan vacías.

La vista previa y las exportaciones PNG, JPG y PDF del modo **Patrón** incluyen los símbolos. El modo **Imagen** conserva solo los píxeles. Con la función activada, **Copiar HEX** también incluye la correspondencia de símbolos de los colores activos.

## Opciones

- Lienzos de **1 a 512 cuadros por lado**, con ancho y alto independientes.
- Preajustes de 16, 32, 48 y 64 cuadros.
- Encuadre ajustado con margen transparente, relleno con recorte o estiramiento.
- Máximo de 2–64 colores mediante median cut ponderado.
- Color dominante por casilla, muestreo con promedio o vecino más cercano y tramado Floyd–Steinberg opcional.
- Patrón exportable con cuadros de 8–32 px; imagen sin cuadrícula a escala de 1× a 32×. Máximo de 8192 px por lado, incluidos los márgenes del patrón.
- PNG y PDF en modo Imagen conservan las casillas vacías transparentes. El patrón usa el fondo elegido (blanco inicialmente). JPG en modo Imagen compone sobre blanco y usa compresión con pérdida.

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
- `Sources/Pixelart/PatternRenderer.swift`: rectángulos sólidos, fondo configurable, líneas sin suavizado, coordenadas y símbolos, compartidos entre vista y exportación.
- `Sources/Pixelart/GridCanvas.swift`: lienzo vectorial, zoom e interacción por fila y columna.
- `Sources/Pixelart/GridDocument.swift`: geometría de celdas, historial de cambios y formato editable validado.
- `Sources/Pixelart/ImageExporter.swift`: PNG, JPG y PDF vectorial.
- `Sources/Pixelart/AppModel.swift`: importación, tareas cancelables y estado.
- `Sources/Pixelart/ContentView.swift`: interfaz JeXelart en español.
- `Tests/PixelEngineChecks.swift`: 17 comprobaciones de dimensiones, orientación, paleta, alfa binario, edición, historial, geometría, documentos y exportaciones con lectura de vuelta.
- `scripts/` y `packaging/`: creación del paquete `.app`.

Las compilaciones, ejemplos e imágenes generadas quedan excluidos de Git.
