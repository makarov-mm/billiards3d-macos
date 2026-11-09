// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Billiards3D",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Billiards3D",
            resources: [
                .copy("Resources/Shaders"),
                .copy("Resources/billiards3d.png"),
            ]
        ),
    ]
)
