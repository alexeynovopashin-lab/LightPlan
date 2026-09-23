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
        // Холст карты (итерация 4, docs/17 § 10): первая внешняя зависимость
        // продукта. Версия прибита — та же, что мерилась в песочнице.
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution", exact: "6.31.0"),
    ],
    targets: [
        .target(
            name: "LightPlanUI",
            dependencies: [
                .product(name: "LightPlanCore", package: "LightPlanCore"),
                .product(name: "LightPlanDomain", package: "LightPlanDomain"),
                .product(name: "LightPlanTimeline", package: "LightPlanTimeline"),
                .product(name: "LightPlanData", package: "LightPlanData"),
                "LightPlanMapCanvas",
            ],
            resources: [.process("Resources")]
        ),
        // Поставщики холста за одним видом: выше этого модуля ни MapLibre, ни
        // MapKit не поднимаются (docs/17 § 10, держит Tools/check_boundaries.sh).
        // MapLibre — библиотека на Objective-C без `Sendable`: строгая
        // конкурентность ослаблена здесь, в одном модуле, а не в проекте.
        .target(
            name: "LightPlanMapCanvas",
            dependencies: [
                .product(name: "MapLibre", package: "maplibre-gl-native-distribution",
                         condition: .when(platforms: [.iOS])),
            ],
            resources: [.copy("Resources/style_dark.json"), .copy("Resources/style_light.json")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LightPlanUITests",
            dependencies: ["LightPlanUI"],
            // Ответы веба на корпус названий, эталонный лист знаков и разметка
            // прибора карты читаются по #filePath, а не ресурсом: это не сборочные файлы.
            exclude: ["point_sign.json", "icons_ref.png", "icons_ref.json", "map_scene_ref.json"],
            resources: [.process("Resources")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
