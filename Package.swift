// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pixelart",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Pixelart", targets: ["Pixelart"])],
    targets: [
        .executableTarget(name: "Pixelart"),
        .testTarget(name: "PixelartTests", dependencies: ["Pixelart"])
    ]
)
