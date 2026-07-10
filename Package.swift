// swift-tools-version: 5.10

// The binary target URL and checksum are stamped by the "SPM Release"
// workflow — do not edit them by hand. The buildable source package lives
// at packages/font-manager/src-native/ios/FontManager.

import PackageDescription

let package = Package(
    name: "FontManager",
    platforms: [
        .iOS(.v13),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "FontManager",
            targets: ["FontManager"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "FontManager",
            url: "https://github.com/NativeScript/font-manager/releases/download/1.0.13/FontManager.xcframework.zip",
            checksum: "599f02629cfc43400d295326d1d6dee05ebe97755419377830ad52602ff1b99d"
        ),
    ]
)
