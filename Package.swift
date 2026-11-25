// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RemindMeet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "RemindMeet", path: "Sources/RemindMeet")
    ]
)
