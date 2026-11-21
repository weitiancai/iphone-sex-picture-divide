// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PictureDivideCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PictureDivideCore", targets: ["PictureDivideCore"]),
        .executable(name: "pdctl", targets: ["PDCtl"]),
        .executable(name: "pdctl-selftest", targets: ["PDSelfTest"])
    ],
    targets: [
        .target(
            name: "PictureDivideCore",
            path: "Sources/PictureDivideCore"
        ),
        .executableTarget(
            name: "PDCtl",
            dependencies: ["PictureDivideCore"],
            path: "Sources/PDCtl"
        ),
        .executableTarget(
            name: "PDSelfTest",
            dependencies: ["PictureDivideCore"],
            path: "Sources/PDSelfTest"
        ),
        .testTarget(
            name: "PictureDivideCoreTests",
            dependencies: ["PictureDivideCore"],
            path: "Tests/PictureDivideCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
