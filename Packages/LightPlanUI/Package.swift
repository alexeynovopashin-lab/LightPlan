// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LightPlanUI",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LightPlanUI", targets: ["LightPlanUI"]),
    ],
    dependencies: [
        .package(path: "../LightPlanCore"),
        .package(path: "../LightPlanDomain"),
        .package(path: "../LightPlanTimeline"),
        .package(path: "../LightPlanData"),
    ],
    targets: [
        .target(
            name: "LightPlanUI",
            dependencies: [
                .product(name: "LightPlanCore", package: "LightPlanCore"),
                .product(name: "LightPlanDomain", package: "LightPlanDomain"),
                .product(name: "LightPlanTimeline", package: "LightPlanTimeline"),
                .product(name: "LightPlanData", package: "LightPlanData"),
            ]
        ),
        .testTarget(name: "LightPlanUITests", dependencies: ["LightPlanUI"]),
    ],
    swiftLanguageModes: [.v6]
)
