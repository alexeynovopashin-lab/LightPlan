// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LightPlanUI",
    defaultLocalization: "en",
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
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LightPlanUITests",
            dependencies: ["LightPlanUI"],
            // Ответы веба на корпус названий и эталонный лист знаков читаются по
            // #filePath, а не ресурсом: это не сборочные файлы.
            exclude: ["point_sign.json", "icons_ref.png", "icons_ref.json"],
            resources: [.process("Resources")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
