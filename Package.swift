// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ForexMarketHours",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ForexMarketHours", targets: ["ForexMarketHours"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0")
    ],
    targets: [
        .executableTarget(
            name: "ForexMarketHours",
            dependencies: ["Sparkle"],
            path: "Sources/ForexMarketHours",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
