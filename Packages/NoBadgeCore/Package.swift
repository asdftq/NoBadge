// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NoBadgeCore", platforms: [.macOS(.v15)],
    products: [.library(name: "NoBadgeCore", targets: ["NoBadgeCore"]), .executable(name: "NoBadgeLab", targets: ["NoBadgeLab"])],
    targets: [.target(name: "NoBadgeCore"), .executableTarget(name: "NoBadgeLab", dependencies: ["NoBadgeCore"]), .testTarget(name: "NoBadgeCoreTests", dependencies: ["NoBadgeCore"])]
)
