// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VerbaMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VerbaMac", targets: ["VerbaMac"])
    ],
    targets: [
        .executableTarget(
            name: "VerbaMac",
            path: "Sources/VerbaMac",
            exclude: [],
            sources: nil,
            resources: [
                .copy("Resources/Lexicon"),
                .copy("Resources/WORDS")
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("Compression")
            ]
        )
    ]
)
