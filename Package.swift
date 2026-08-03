// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetFareCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "NetFareCore", targets: ["NetFareCore"])
    ],
    targets: [
        .target(
            name: "NetFareCore",
            path: "NetFareCore"
        ),
        .testTarget(
            name: "NetFareCoreTests",
            dependencies: ["NetFareCore"],
            path: "NetFareCoreTests"
        )
    ]
)
