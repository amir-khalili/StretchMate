// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StretchMate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "StretchMate",
            path: "Sources/StretchMate"
        )
    ]
)
