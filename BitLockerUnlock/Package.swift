// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BitLockerUnlock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BitLockerUnlock", targets: ["BitLockerUnlock"])
    ],
    targets: [
        .executableTarget(
            name: "BitLockerUnlock",
            path: "Sources/BitLockerUnlock",
            exclude: [
                "Screens/.gitkeep",
                "Chrome/.gitkeep"
            ],
            linkerSettings: [
                .linkedFramework("DiskArbitration"),
                .linkedFramework("CoreFoundation")
            ]
        )
    ]
)
