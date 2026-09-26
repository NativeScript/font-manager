// swift-tools-version: 5.10

// The binary target URL and checksum are stamped by the "SPM Release"
// workflow — do not edit them by hand. The buildable source package lives
// at packages/font-manager/src-native/ios/FontManager.

import PackageDescription

let package = Package(
    name: "FontManager",
    platforms: [
        .iOS(.v13),
        .visionOS(.v1),
        .tvOS(.v13)
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
            url: "https://github.com/NativeScript/font-manager/releases/download/1.0.17/FontManager.xcframework.zip",
            checksum: "77e156b2ab59610a305dfb4b57e513ece0f76ee3c84c96cd9463691a76f5c6a8"
        ),
    ]
)
