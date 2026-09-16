// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "vision_scan",
    platforms: [
        .iOS("12.0")
    ],
    products: [
        .library(name: "vision-scan", targets: ["vision_scan"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .binaryTarget(
            name: "vision_scan_native",
            url: "https://github.com/masterjayr/vision_scan/releases/download/v0.0.9/vision_scan_native-ios.zip",
            checksum: "0a5307816b19bf48670b3ad5821e0aa9bae5cdd1abbe5e58d2c42606ef403e1f"
        ),
        .target(
            name: "vision_scan",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "vision_scan_native"
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("UIKit")
            ]
        )
    ]
)
