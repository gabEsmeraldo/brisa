// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Brisa",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Brisa", path: "Sources/Brisa")
    ]
)
