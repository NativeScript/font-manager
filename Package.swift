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
            url: "https://github.com/NativeScript/font-manager/releases/download/0.0.0/FontManager.xcframework.zip",
            checksum: "0000000000000000000000000000000000000000000000000000000000000000"
        ),
    ]
)
