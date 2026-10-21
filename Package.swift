// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JeXelart",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "JeXelart", targets: ["JeXelart"])],
    targets: [
        .executableTarget(name: "JeXelart", path: "Sources/Pixelart")
    ]
)
