// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasswardsCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "PasswardsCore", targets: ["PasswardsCore"]),
        .library(name: "PasswardsOrchestration", targets: ["PasswardsOrchestration"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "PasswardsCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [
                .copy("Resources/eff_large_wordlist.txt"),
                .copy("Resources/top100k_passwords.txt"),
                .copy("Resources/2fa_directory.json"),
                .copy("Resources/public_suffix_list.dat"),
            ]
        ),
        // Cross-platform orchestration shared by the macOS and iOS apps: account
        // lifecycle + vault data/view-model + the platform-service protocol seams.
        // May import SwiftUI/Observation; never AppKit/UIKit (those stay app-side).
        .target(
            name: "PasswardsOrchestration",
            dependencies: ["PasswardsCore"]
        ),
        .testTarget(
            name: "PasswardsCoreTests",
            dependencies: [
                "PasswardsCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .testTarget(
            name: "PasswardsOrchestrationTests",
            dependencies: ["PasswardsOrchestration"]
        ),
    ]
)
