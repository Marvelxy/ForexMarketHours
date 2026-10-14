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
    targets: [
        .executableTarget(
            name: "ForexMarketHours",
            path: "Sources/ForexMarketHours",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
