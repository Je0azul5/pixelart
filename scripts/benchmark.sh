#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/performance
swiftc -O -swift-version 6 -parse-as-library \
    Sources/Pixelart/PixelEngine.swift \
    Sources/Pixelart/GridDocument.swift \
    Sources/Pixelart/PatternRenderer.swift \
    Sources/Pixelart/ImageExporter.swift \
    Tests/PerformanceChecks.swift \
    -o .build/performance/checks
if [ "$#" -gt 0 ]; then
    /usr/bin/time -l .build/performance/checks "$1"
else
    for scenario in convert dither palette clipped history pdf; do
        /usr/bin/time -l .build/performance/checks "$scenario"
    done
fi
