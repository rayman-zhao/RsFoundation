// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RsFoundation",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "RsFoundation",
            targets: ["RsFoundation"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.15.0"),
    ],
    targets: [
        .target(
            name: "RsFoundation",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(
                    name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.windows])
                ),
            ],
        ),
        .testTarget(
            name: "RsFoundationTests",
            dependencies: ["RsFoundation"],
            resources: [
                .copy("Resources/")
            ],
        ),
    ]
)
