// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SnipText",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Minor updates only: HotkeyStatus listens for a notification that is internal to it.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", .upToNextMinor(from: "2.4.0")),
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
