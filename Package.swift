// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Blip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "blip", targets: ["blip"]),
        .executable(name: "BlipApp", targets: ["BlipApp"]),
    ],
    targets: [
        .target(name: "BlipShared"),
        .executableTarget(name: "blip", dependencies: ["BlipShared"]),
        .executableTarget(name: "BlipApp", dependencies: ["BlipShared"]),
    ]
)
