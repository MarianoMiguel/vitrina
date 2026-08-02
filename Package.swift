// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "vitrina",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "vitrina", targets: ["DynamicShareTarget"])
    ],
    targets: [
        .target(
            name: "VirtualDisplayShim",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreGraphics")
            ]
        ),
        .executableTarget(
            name: "DynamicShareTarget",
            dependencies: ["VirtualDisplayShim"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
