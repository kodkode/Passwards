// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TwoPasswordCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TwoPasswordCore", targets: ["TwoPasswordCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "TwoPasswordCore",
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
        .testTarget(
            name: "TwoPasswordCoreTests",
            dependencies: [
                "TwoPasswordCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
