// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Estris",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Estris", path: "Sources/Estris")
    ]
)
