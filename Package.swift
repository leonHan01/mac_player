// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacVideoPlayer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacVideoPlayer", targets: ["MacVideoPlayer"])
    ],
    targets: [
        .executableTarget(
            name: "MacVideoPlayer",
            path: "Sources/MacVideoPlayer"
        )
    ]
)
