// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotchDJ",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchDJ", targets: ["NotchDJ"])
    ],
    targets: [
        .executableTarget(
            name: "NotchDJ",
            path: "Sources/NotchDJ",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
