// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PasteRing",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "PasteRing", path: "Sources/PasteRing")
    ]
)
