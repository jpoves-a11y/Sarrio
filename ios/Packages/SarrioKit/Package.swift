// swift-tools-version: 6.0
import PackageDescription

// Lógica pura (sin UIKit/HealthKit/Mapbox): geometría, parseo de tracks y detección de cumbres.
// Se prueba con `swift test` en macOS o Linux.
let package = Package(
    name: "SarrioKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SarrioKit", targets: ["SarrioKit"])],
    targets: [
        .target(name: "SarrioKit"),
        .testTarget(
            name: "SarrioKitTests",
            dependencies: ["SarrioKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
