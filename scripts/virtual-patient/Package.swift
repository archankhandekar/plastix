// swift-tools-version: 5.9
// Virtual-patient renderer. A separate macOS-only package: it is not part of the root
// package, the app scheme or the Linux CI. See README.md in this directory.
import PackageDescription

let package = Package(
    name: "virtual-patient",
    platforms: [.macOS(.v13)],
    dependencies: [
        // The explicit name is required: path identity otherwise follows the checkout
        // directory name, which differs between worktrees.
        .package(name: "SymmetryPrototype", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "render",
            dependencies: [.product(name: "SymmetryCore", package: "SymmetryPrototype")],
            path: "Sources/render"
        ),
    ]
)
