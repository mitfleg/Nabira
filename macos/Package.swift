// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nabira",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Nabira",
            path: "Sources/Nabira",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "NabiraTests",
            dependencies: ["Nabira"],
            path: "Tests/NabiraTests"
        ),
    ]
)
