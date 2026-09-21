// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemoteBuddy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "RemoteBuddy", path: "Sources/RemoteBuddy"),
        .testTarget(name: "RemoteBuddyTests", dependencies: ["RemoteBuddy"], path: "Tests/RemoteBuddyTests")
    ]
)
