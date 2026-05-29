// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PaperBot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PaperBot",
            path: "Sources/PaperBot"
        )
    ]
)
