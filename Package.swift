// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LaTeXaP",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LaTeXaP", targets: ["LaTeXaP"])
    ],
    targets: [
        .executableTarget(
            name: "LaTeXaP",
            path: "Sources/LaTeXaP",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .testTarget(
            name: "LaTeXaPTests",
            dependencies: ["LaTeXaP"],
            path: "Tests/LaTeXaPTests",
            swiftSettings: [
                .unsafeFlags([
                    "-load-plugin-library",
                    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
                ])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
