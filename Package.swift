// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Multitude",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Multitude"
        )
    ]
)
