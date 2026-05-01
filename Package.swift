// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "glance-md",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "glance-md", targets: ["GlanceMDApp"]),
        .library(name: "GlanceMDCore", targets: ["GlanceMDCore"])
    ],
    targets: [
        .target(name: "GlanceMDCore"),
        .executableTarget(
            name: "GlanceMDApp",
            dependencies: ["GlanceMDCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GlanceMDCoreTests",
            dependencies: ["GlanceMDCore"]
        )
    ]
)
