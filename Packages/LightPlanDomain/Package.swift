// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LightPlanDomain",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LightPlanDomain", targets: ["LightPlanDomain"]),
    ],
    dependencies: [
        .package(path: "../LightPlanCore"),
    ],
    targets: [
        .target(
            name: "LightPlanDomain",
            dependencies: [
                .product(name: "LightPlanCore", package: "LightPlanCore"),
            ]
        ),
        .testTarget(name: "LightPlanDomainTests", dependencies: ["LightPlanDomain"]),
    ],
    swiftLanguageModes: [.v6]
)
