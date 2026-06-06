// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FirepowerShared",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "FirepowerShared", targets: ["FirepowerShared"]),
    ],
    targets: [
        .target(
            name: "FirepowerShared",
            path: "Sources/FirepowerShared"
        ),
        .testTarget(
            name: "FirepowerSharedTests",
            dependencies: ["FirepowerShared"],
            path: "Tests/FirepowerSharedTests"
        ),
    ]
)
