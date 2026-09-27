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
            url: "https://github.com/NativeScript/font-manager/releases/download/1.0.20/FontManager.xcframework.zip",
            checksum: "d15472c28faf4805a5c23c4e2195e902de945bce12f40bf0de981bee2b42bf4b"
        ),
    ]
)
