// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RegardingWorkMeetings",
    platforms: [.macOS(.v15)],
    products: [
        .executable(
            name: "regardingwork-meetings",
            targets: ["RegardingWorkMeetings"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "RegardingWorkMeetings",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist into the binary so TCC can attribute the
                // system-audio-capture permission to the executable itself when it
                // runs as a LaunchAgent (no .app bundle to carry a plist).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/RegardingWorkMeetings/Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "RegardingWorkMeetingsTests",
            dependencies: ["RegardingWorkMeetings"]
        ),
    ]
)
