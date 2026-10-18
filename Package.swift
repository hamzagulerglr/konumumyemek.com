// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Lumen",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Lumen", targets: ["Lumen"])
    ],
    targets: [
        .executableTarget(
            name: "Lumen",
            path: "Lumen",
            exclude: [
                "Assets.xcassets",
                "Lumen.entitlements",
                "Fonts"
            ]
        )
    ]
)
