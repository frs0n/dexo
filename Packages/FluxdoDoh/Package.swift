// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FluxdoDoh",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "DohProxy",
            targets: ["DohProxy"]
        ),
    ],
    targets: [
        // Precompiled Rust static library + C header
        .binaryTarget(
            name: "DohProxyFFI",
            path: "Artifacts/DohProxyFFI.xcframework"
        ),
        // Thin C shim that re-exports the header so Swift can import it
        .target(
            name: "CDohProxy",
            dependencies: ["DohProxyFFI"],
            path: "Sources/CDohProxy",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("resolv"),
                .linkedLibrary("c++"),
            ]
        ),
        // Swift wrapper
        .target(
            name: "DohProxy",
            dependencies: ["CDohProxy"],
            path: "Sources/DohProxy"
        ),
    ]
)
