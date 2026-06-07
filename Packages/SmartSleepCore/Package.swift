// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SmartSleepCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SmartSleepCore", targets: ["SmartSleepCore"])
    ],
    targets: [
        .target(name: "SmartSleepCore"),
        .testTarget(
            name: "SmartSleepCoreTests",
            dependencies: ["SmartSleepCore"]
        )
    ]
)

