// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KerfKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "KerfKit", targets: ["KerfKit"]),
    ],
    targets: [
        .target(name: "KerfKit"),
        .testTarget(name: "KerfKitTests", dependencies: ["KerfKit"]),
    ]
)
