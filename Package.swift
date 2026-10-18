// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Luma",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Luma", targets: ["LumaApp"]), .executable(name: "luma-rules", targets: ["LumaRuleValidator"])],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(name: "LumaCore", dependencies: [.product(name: "Yams", package: "Yams"), .product(name: "GRDB", package: "GRDB.swift")], resources: [.copy("Resources/CleanupRules.yaml")]),
        .executableTarget(name: "LumaRuleValidator", dependencies: ["LumaCore"]),
        .executableTarget(name: "LumaApp", dependencies: ["LumaCore"]),
        .testTarget(name: "LumaCoreTests", dependencies: ["LumaCore", .product(name: "GRDB", package: "GRDB.swift")], resources: [.copy("Fixtures/RulesBaseline.json")])
    ]
)
