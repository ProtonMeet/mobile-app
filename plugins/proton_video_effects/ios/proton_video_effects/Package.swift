// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Sources under Sources/ are symlinks to darwin/Classes and ios/Classes — the CocoaPods build
// (macOS) uses the same files.
// VendoredFrameworks/ and the tflite models are staged by scripts/spm/prepare_ios_spm.sh.

import PackageDescription

let package = Package(
    name: "proton_video_effects",
    platforms: [
        .iOS("15.0"),
    ],
    products: [
        .library(name: "proton-video-effects", targets: ["proton_video_effects"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Resolved by the Flutter tool to the flutter_webrtc plugin package.
        .package(name: "flutter_webrtc", path: "../flutter_webrtc-1.6.2+hotfix.4"),
    ],
    targets: [
        .binaryTarget(
            name: "MediaPipeTasksCommon",
            path: "VendoredFrameworks/MediaPipeTasksCommon.xcframework"),
        .binaryTarget(
            name: "MediaPipeTasksVision",
            path: "VendoredFrameworks/MediaPipeTasksVision.xcframework"),
        // MediaPipe registers its calculators from static initialisers, so the graph archive has
        // to be force-loaded or segmentation fails to find them at runtime.
        .binaryTarget(
            name: "MediaPipeTasksCommonGraph",
            path: "VendoredFrameworks/MediaPipeTasksCommonGraph.xcframework"),
        .target(
            name: "proton_video_effects",
            dependencies: [
                "MediaPipeTasksVision",
                "MediaPipeTasksCommon",
                "MediaPipeTasksCommonGraph",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "flutter-webrtc", package: "flutter_webrtc"),
            ],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("Vision"),
                // Xcode extracts the selected xcframework slice into BUILT_PRODUCTS_DIR, which
                // keeps this one path valid for both device and simulator.
                .unsafeFlags([
                    "-Wl,-force_load,${BUILT_PRODUCTS_DIR}/libMediaPipeTasksCommonGraph.a"
                ]),
            ]
        ),
    ]
)
