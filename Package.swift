// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Luma",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Luma", targets: ["LumaApp"])],
    targets: [
        .target(name: "LumaCore"),
        .executableTarget(name: "LumaApp", dependencies: ["LumaCore"]),
        .testTarget(name: "LumaCoreTests", dependencies: ["LumaCore"])
    ]
)
