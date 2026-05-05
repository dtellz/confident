// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ProximityServer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ProximityServer",
            path: "Sources/ProximityServer"
        )
    ]
)
