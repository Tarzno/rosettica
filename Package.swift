// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rosettica",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "RosetticaCore",
            path: "Sources/RosetticaCore"
        ),
        .executableTarget(
            name: "Rosettica",
            dependencies: ["RosetticaCore"],
            path: "Sources/Rosettica"
        ),
        // Type-checked here for convenience; the .saver bundle itself is
        // assembled by Scripts/build-saver.sh, which compiles these sources
        // together with RosetticaCore into a loadable bundle.
        .target(
            name: "RosetticaSaver",
            dependencies: ["RosetticaCore"],
            path: "Sources/RosetticaSaver",
            linkerSettings: [.linkedFramework("ScreenSaver")]
        ),
        .testTarget(
            name: "RosetticaCoreTests",
            dependencies: ["RosetticaCore"],
            path: "Tests/RosetticaCoreTests"
        ),
    ]
)
