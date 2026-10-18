// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnipText",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/jaywcjlove/PermissionFlow", from: "2.11.3"),
    ],
    targets: [
        .target(name: "SnipTextKit"),
        .executableTarget(
            name: "SnipText",
            dependencies: [
                "SnipTextKit",
                "KeyboardShortcuts",
                .product(name: "PermissionFlow", package: "PermissionFlow"),
            ]
        ),
        .testTarget(name: "SnipTextKitTests", dependencies: ["SnipTextKit"]),
    ]
)
