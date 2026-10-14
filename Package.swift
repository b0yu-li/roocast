// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Roocast",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Roocast",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "RoocastTests",
            dependencies: ["Roocast"]
        )
    ]
)
