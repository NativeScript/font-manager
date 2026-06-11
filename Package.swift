// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "FontManager",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "FontManager",
            targets: ["FontManager"]
        ),
    ],
    targets: [
        .target(
            name: "FontManager",
            path: "packages/font-manager/src-native/ios/FontManager/Sources/FontManager",
            publicHeadersPath: ".",
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .testTarget(
            name: "FontManagerTests",
            dependencies: ["FontManager"],
            path: "packages/font-manager/src-native/ios/FontManager/Tests/FontManagerTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
