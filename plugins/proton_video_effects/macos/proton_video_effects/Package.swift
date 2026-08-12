// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Sources under Sources/ are symlinks to darwin/Classes and macos/Classes — the CocoaPods build
// uses the same files.
// Nothing to vendor here: the MediaPipe segmenter is iOS-only, so macOS takes the Vision path in
// MeetBackgroundBlurMediaPipeEngine and needs no tflite models.

import PackageDescription

let package = Package(
    name: "proton_video_effects",
    platforms: [
        .macOS("12.0"),
    ],
    products: [
        .library(name: "proton-video-effects", targets: ["proton_video_effects"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Resolved by the Flutter tool to the flutter_webrtc plugin package.
        .package(name: "flutter_webrtc", path: "../flutter_webrtc-1.6.0"),
    ],
    targets: [
        .target(
            name: "proton_video_effects",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "flutter-webrtc", package: "flutter_webrtc"),
            ],
            linkerSettings: [
                .linkedFramework("CoreImage"),
                .linkedFramework("Metal"),
                .linkedFramework("Vision"),
            ]
        ),
    ]
)
