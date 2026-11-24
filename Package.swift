// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MaxNinesMenuBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Everything that talks to the server or decides what to show, so it can
        // be tested without the app.
        .target(name: "MaxNinesKit"),
        .executableTarget(name: "MaxNinesMenuBar", dependencies: ["MaxNinesKit"]),
        .testTarget(name: "MaxNinesKitTests", dependencies: ["MaxNinesKit"]),
    ],
    swiftLanguageModes: [.v5]
)
