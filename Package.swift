// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Mischpult",
    // Process-Taps (Lautstärke pro App) gibt es erst ab macOS 14.2.
    platforms: [.macOS("14.2")],
    products: [.executable(name: "Mischpult", targets: ["Mischpult"])],
    targets: [
        .target(name: "MischpultAtomics"),
        .target(name: "MischpultCore", dependencies: ["MischpultAtomics"]),
        .executableTarget(name: "Mischpult", dependencies: ["MischpultCore"]),
        .testTarget(name: "MischpultCoreTests", dependencies: ["MischpultCore"])
    ]
)
