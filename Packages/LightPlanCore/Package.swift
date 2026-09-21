// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LightPlanCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LightPlanCore", targets: ["LightPlanCore"]),
    ],
    targets: [
        .target(name: "LightPlanCore", resources: [.copy("Eclipse/Resources/eclipses.json")]),
        .testTarget(name: "LightPlanCoreTests", dependencies: ["LightPlanCore"]),
    ],
    swiftLanguageModes: [.v6]
)
