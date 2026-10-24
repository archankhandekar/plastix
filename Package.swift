// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SymmetryPrototype",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "SymmetryCore", targets: ["SymmetryCore"]),
    ],
    targets: [
        .target(name: "SymmetryCore", path: "Sources/SymmetryCore"),
        .testTarget(name: "SymmetryCoreTests", dependencies: ["SymmetryCore"], path: "Tests/SymmetryCoreTests"),
    ]
)
