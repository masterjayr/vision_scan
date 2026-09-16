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
            checksum: "c09096e08a7ba953cfaca41b92cc1d05eb4bdd1aaed7376ef8baa3e1a0389afc"
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
