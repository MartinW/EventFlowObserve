// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EventFlowObserve",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "EventFlowObserve",
            targets: ["EventFlowObserve"]
        ),
    ],
    targets: [
        .target(
            name: "EventFlowObserve",
            dependencies: []
        ),
        .testTarget(
            name: "EventFlowObserveTests",
            dependencies: ["EventFlowObserve"]
        ),
    ]
)
