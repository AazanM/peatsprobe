// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PeatsProbe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PeatsProbe", targets: ["PeatsProbe"])
    ],
    targets: [
        .executableTarget(
            name: "PeatsProbe",
            path: "Sources/PeatsProbe"
        )
    ]
)
