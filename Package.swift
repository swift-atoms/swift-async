// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-async",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "Async Primitive", targets: ["Async Primitive"]),
        .library(name: "Async Callback", targets: ["Async Callback"]),
        .library(name: "Async Cancellation", targets: ["Async Cancellation"]),
        .library(name: "Async Continuation", targets: ["Async Continuation"]),
        .library(name: "Async Demand", targets: ["Async Demand"]),
        .library(name: "Async Lifecycle", targets: ["Async Lifecycle"]),
        .library(name: "Async Precedence", targets: ["Async Precedence"]),
        .library(name: "Async Mutex", targets: ["Async Mutex"]),
        .library(name: "Async Promise", targets: ["Async Promise"]),
        .library(name: "Async Publication", targets: ["Async Publication"]),
        .library(name: "Async Completion", targets: ["Async Completion"]),
        .library(name: "Async", targets: ["Async"]),
        .library(name: "Async Test Support", targets: ["Async Test Support"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-atoms/swift-buffer.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-queue.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-tagged.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Async Primitive",
            dependencies: [
            ],
            path: "Sources/Async Primitive"
        ),
        .target(
            name: "Async Callback",
            dependencies: [
                .target(name: "Async Primitive"),
            ],
            path: "Sources/Async Callback"
        ),
        .target(
            name: "Async Cancellation",
            dependencies: [
                .target(name: "Async Mutex"),
                .target(name: "Async Primitive"),
            ],
            path: "Sources/Async Cancellation"
        ),
        .target(
            name: "Async Continuation",
            dependencies: [
                .target(name: "Async Primitive"),
            ],
            path: "Sources/Async Continuation"
        ),
        .target(
            name: "Async Demand",
            dependencies: [
                .target(name: "Async Primitive"),
            ],
            path: "Sources/Async Demand"
        ),
        .target(
            name: "Async Lifecycle",
            dependencies: [
                .target(name: "Async Primitive"),
            ],
            path: "Sources/Async Lifecycle"
        ),
        .target(
            name: "Async Precedence",
            dependencies: [
                .target(name: "Async Primitive"),
            ],
            path: "Sources/Async Precedence"
        ),
        .target(
            name: "Async Mutex",
            dependencies: [
                .target(name: "Async Primitive"),
            ],
            path: "Sources/Async Mutex"
        ),
        .target(
            name: "Async Promise",
            dependencies: [
                .target(name: "Async Continuation"),
                .target(name: "Async Mutex"),
                .target(name: "Async Primitive"),
            ],
            path: "Sources/Async Promise"
        ),
        .target(
            name: "Async Publication",
            dependencies: [
                .target(name: "Async Mutex"),
                .target(name: "Async Primitive"),
            ],
            path: "Sources/Async Publication"
        ),
        .target(
            name: "Async Completion",
            dependencies: [
                .target(name: "Async Mutex"),
                .target(name: "Async Primitive"),
            ],
            path: "Sources/Async Completion"
        ),
        .target(
            name: "Async",
            dependencies: [
                .target(name: "Async Callback"),
                .target(name: "Async Cancellation"),
                .target(name: "Async Completion"),
                .target(name: "Async Continuation"),
                .target(name: "Async Demand"),
                .target(name: "Async Lifecycle"),
                .target(name: "Async Mutex"),
                .target(name: "Async Precedence"),
                .target(name: "Async Primitive"),
                .target(name: "Async Promise"),
                .target(name: "Async Publication"),
            ],
            path: "Sources/Async"
        ),
        .testTarget(
            name: "Async Tests",
            dependencies: [
                .target(name: "Async"),
                .target(name: "Async Test Support"),
            ],
            path: "Tests/Async Tests"
        ),
        .target(
            name: "Async Test Support",
            dependencies: [
                .product(name: "Buffer Test Support", package: "swift-buffer"),
                .product(name: "Queue Test Support", package: "swift-queue"),
                .product(name: "Tagged Test Support", package: "swift-tagged"),
                .target(name: "Async"),
            ],
            path: "Tests/Support"
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]

    let package: [SwiftSetting] = [
        .enableExperimentalFeature("RawLayout")
    ]

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
