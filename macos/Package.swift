// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "idkthen",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "idkthen", targets: ["IdkthenApp"])],
    targets: [
        .target(name: "IdkthenCore"),
        .executableTarget(name: "IdkthenApp", dependencies: ["IdkthenCore"]),
        .testTarget(name: "IdkthenCoreTests", dependencies: ["IdkthenCore"])
    ]
)
