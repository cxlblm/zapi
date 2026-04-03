// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Zapi",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ZapiCore",
            targets: ["ZapiCore"]
        ),
        .executable(
            name: "ZapiApp",
            targets: ["ZapiApp"]
        ),
        .executable(
            name: "ZapiSmokeChecks",
            targets: ["ZapiSmokeChecks"]
        )
    ],
    targets: [
        .target(
            name: "ZapiCore"
        ),
        .executableTarget(
            name: "ZapiApp",
            dependencies: ["ZapiCore"]
        ),
        .executableTarget(
            name: "ZapiSmokeChecks",
            dependencies: ["ZapiCore"]
        )
    ]
)
