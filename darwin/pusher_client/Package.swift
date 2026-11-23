// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "pusher_client",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15")
    ],
    products: [
        .library(name: "pusher-client", targets: ["pusher_client"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/pusher/pusher-websocket-swift.git", .upToNextMinor(from: "10.1.10")),
        // Same range PusherSwift 10.1.10 uses; imported for SubscriptionDataNormalizer.
        .package(url: "https://github.com/pusher/NWWebSocket.git", .upToNextMajor(from: "0.5.10")),
        // PusherSwift allows any TweetNacl 1.x, but 1.3.0 raised its minimum to iOS 15 / macOS 12.
        // Constrain resolution to 1.2.x, the last line supporting iOS 13 / macOS 10.15
        // (not used directly by this plugin).
        .package(url: "https://github.com/pusher/tweetnacl-swiftwrap", .upToNextMinor(from: "1.2.0"))
    ],
    targets: [
        .target(
            name: "pusher_client",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "PusherSwift", package: "pusher-websocket-swift"),
                .product(name: "NWWebSocket", package: "NWWebSocket")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
