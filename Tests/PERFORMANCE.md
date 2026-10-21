# CPU y memoria de JeXelart

Medición local del 21 de octubre de 2026, macOS ARM64, Swift con `-O`. Referencia: commit `dcbcb3c`. Misma máquina y mismo programa de medición antes y después. Cada escenario corre en un proceso independiente; RSS incluye el proceso completo, sus entradas y las bibliotecas. Los tiempos de la tabla corresponden al cuerpo del escenario, sin compilación ni lanzamiento.

| Escenario de 512 × 512 | Antes (s) | Después (s) | Pico RSS antes (MiB) | Pico RSS después (MiB) |
| --- | ---: | ---: | ---: | ---: |
| Conversión dominante, 32 colores | 0,6558 | 0,0842 | 33,4 | 34,7 |
| Conversión dominante con tramado | 0,7264 | 0,0912 | 48,4 | 34,7 |
| Consultar la paleta 200 veces | 0,7915 | 0,0001 | 8,6 | 8,4 |
| Dibujar una ventana de 256 × 256, 20 veces | 1,8529 | 0,0086 | 10,3 | 10,2 |
| 24 operaciones que repintan el lienzo completo | 0,3537 | 0,6132 | 200,7 | 56,7 |
| PDF vectorial con cuadros de 15 px | 3,6251 | 0,1864 | 316,6 | 13,4 |

Son mediciones puntuales de cargas sintéticas, no una promesa sobre todas las imágenes ni sobre el uso en reposo. La conversión sin tramado utiliza algo más de RAM en esta entrada; el seguimiento incremental de colores añade trabajo al repintado masivo. A cambio, consultar la paleta durante la interacción deja de recorrer las 262.144 celdas y el historial tiene un límite de memoria. La prueba del historial conserva todas las acciones en la referencia; la versión optimizada descarta las más antiguas al llegar al presupuesto de 16 MiB de cambios compactos (más estructuras y memoria temporal), manteniendo hasta 100 acciones pequeñas.

Se comprobó que los colores de 12 conversiones coinciden byte a byte con la referencia: las tres opciones de encuadre, dominante o promedio y tramado activado o desactivado. Las 19 comprobaciones funcionales cubren dimensiones, alfa, edición, historial, paleta incremental, límites de historial, documentos y exportaciones. El dibujo parcial se compara con el dibujo completo, incluyendo símbolos y coordenadas.

```sh
bash scripts/test.sh
bash scripts/benchmark.sh
# Huellas reproducibles del resultado de las 12 conversiones:
bash scripts/benchmark.sh fingerprints
```

El programa de medición está en `Tests/PerformanceChecks.swift`. El script no descarga dependencias ni necesita una imagen externa.
