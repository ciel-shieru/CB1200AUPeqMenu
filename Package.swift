// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CB1200AUPeqMenu",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CB1200AUPeqMenu", targets: ["CB1200AUPeqMenu"])
    ],
    targets: [
        .executableTarget(name: "CB1200AUPeqMenu")
    ]
)
