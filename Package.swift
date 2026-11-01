// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WhatsOn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WhatsOn",
            path: "Sources/WhatsOn"
        )
    ]
)
