// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Sources under Sources/ are symlinks to common/darwin/Classes and common/cpp — the CocoaPods
// build uses the same files via scripts/link_apple_pod_sources.sh.
// VendoredFrameworks/ and the ONNX model are staged by scripts/spm/prepare_macos_spm.sh.

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

func isStaged(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent(path).path)
}

func hasVendoredFramework(_ name: String) -> Bool {
    isStaged("VendoredFrameworks/\(name).xcframework")
}

// Same gating as the podspec: DTLN and DeepFilter are optional, RNNoise is always required.
let dtlnEnabled = hasVendoredFramework("DTLN")
let deepFilterEnabled =
    hasVendoredFramework("DeepFilter") && isStaged("Sources/proton_denoise/Resources/DeepFilterNet3_onnx.tar.gz")

var binaryTargets: [Target] = [
    .binaryTarget(name: "RNNoise", path: "VendoredFrameworks/RNNoise.xcframework"),
]
var nativeDependencies: [Target.Dependency] = ["RNNoise"]
var cppSources = ["proton_rnnoise_c_api.cc", "proton_rnnoise_processor.cc"]
var swiftSettings: [SwiftSetting] = []
var resources: [Resource] = [.process("PrivacyInfo.xcprivacy")]

// The podspec force-loaded these for the same reason: the archives sit ahead of the C shims on
// the link line, so plain -l lookups drop the members that define the native entry points.
// Xcode extracts the selected xcframework slice into BUILT_PRODUCTS_DIR under this name.
var forceLoadedArchives = ["librnnoise.a"]

if dtlnEnabled {
    binaryTargets.append(.binaryTarget(name: "DTLN", path: "VendoredFrameworks/DTLN.xcframework"))
    nativeDependencies.append("DTLN")
    cppSources.append("proton_dtln_c_api.cc")
    // Shared with iOS: the Swift sources gate the dtln-rs processor on this one condition.
    swiftSettings.append(.define("PROTON_DENOISE_DTLN_IOS"))
    forceLoadedArchives.append("libdtln.a")
}

if deepFilterEnabled {
    binaryTargets.append(
        .binaryTarget(name: "DeepFilter", path: "VendoredFrameworks/DeepFilter.xcframework"))
    nativeDependencies.append("DeepFilter")
    cppSources.append("proton_deepfilter_processor.cc")
    swiftSettings.append(.define("PROTON_DENOISE_DEEPFILTER"))
    resources.append(.process("Resources/DeepFilterNet3_onnx.tar.gz"))
}

let package = Package(
    name: "proton_denoise",
    platforms: [
        .macOS("12.0"),
    ],
    products: [
        .library(name: "proton-denoise", targets: ["proton_denoise"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Resolved by the Flutter tool to the flutter_webrtc plugin package.
        .package(name: "flutter_webrtc", path: "../flutter_webrtc-1.6.0"),
    ],
    targets: binaryTargets + [
        .target(
            name: "proton_denoise_cpp",
            dependencies: nativeDependencies,
            sources: cppSources
        ),
        .target(
            name: "proton_denoise",
            dependencies: [
                "proton_denoise_cpp",
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "flutter-webrtc", package: "flutter_webrtc"),
            ],
            resources: resources,
            swiftSettings: swiftSettings,
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("AVFoundation"),
                .unsafeFlags(
                    forceLoadedArchives.map { "-Wl,-force_load,${BUILT_PRODUCTS_DIR}/\($0)" }),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
