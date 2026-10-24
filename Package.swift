// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SymmetryPrototype",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "SymmetryCore", targets: ["SymmetryCore"]),
        .library(name: "SymmetryModels", targets: ["SymmetryModels"]),
    ],
    targets: [
        // Pure geometry, metrics, quality gates, registration and report types.
        .target(name: "SymmetryCore", path: "Sources/SymmetryCore"),
        // Session, capture-set and capture models plus file-based storage. Foundation only.
        .target(name: "SymmetryModels", dependencies: ["SymmetryCore"], path: "Sources/SymmetryModels"),
        .testTarget(name: "SymmetryCoreTests", dependencies: ["SymmetryCore"], path: "Tests/SymmetryCoreTests"),
        .testTarget(name: "SymmetryModelsTests", dependencies: ["SymmetryModels"], path: "Tests/SymmetryModelsTests"),
    ]
)
