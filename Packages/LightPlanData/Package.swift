// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LightPlanData",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LightPlanData", targets: ["LightPlanData"]),
    ],
    dependencies: [
        .package(path: "../LightPlanCore"),
        .package(path: "../LightPlanDomain"),
    ],
    targets: [
        .target(
            name: "LightPlanData",
            dependencies: [
                .product(name: "LightPlanCore", package: "LightPlanCore"),
                .product(name: "LightPlanDomain", package: "LightPlanDomain"),
            ]
        ),
        .testTarget(name: "LightPlanDataTests", dependencies: ["LightPlanData"]),
    ],
    swiftLanguageModes: [.v6]
)
