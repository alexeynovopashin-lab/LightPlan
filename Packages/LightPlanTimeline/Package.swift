// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LightPlanTimeline",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LightPlanTimeline", targets: ["LightPlanTimeline"]),
    ],
    dependencies: [
        .package(path: "../LightPlanCore"),
    ],
    targets: [
        .target(
            name: "LightPlanTimeline",
            dependencies: [
                .product(name: "LightPlanCore", package: "LightPlanCore"),
            ]
        ),
        .testTarget(
            name: "LightPlanTimelineTests",
            dependencies: [
                "LightPlanTimeline",
                .product(name: "LightPlanCore", package: "LightPlanCore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
