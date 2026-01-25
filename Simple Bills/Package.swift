// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimpleBills",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SimpleBills",
            targets: ["SimpleBills"]),
    ],
    targets: [
        .target(
            name: "SimpleBills",
            dependencies: []),
    ]
)
