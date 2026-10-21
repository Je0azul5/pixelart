#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
swiftc -swift-version 6 -parse-as-library \
    Sources/Pixelart/PixelEngine.swift \
    Sources/Pixelart/ImageExporter.swift \
    Sources/Pixelart/PatternRenderer.swift \
    Tests/PixelEngineChecks.swift \
    -o .build/checks/PixelEngineChecks
.build/checks/PixelEngineChecks "$@"
