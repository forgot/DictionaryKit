// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DictionaryKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DictionaryKit", targets: ["DictionaryKit"]),
        .library(name: "DictionaryKitMCP", targets: ["DictionaryKitMCP"]),
        .executable(name: "dictionarykit", targets: ["dictionarykit-cli"]),
        .executable(name: "dictionarykit-mcp-server", targets: ["dictionarykit-mcp-server"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "CDictionaryServicesShim",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreFoundation")
            ]
        ),
        .target(
            name: "DictionaryKit",
            dependencies: ["CDictionaryServicesShim"]
        ),
        // The MCP server lives in a library so it can be tested. Executable targets cannot be
        // imported with @testable, which is why the old server test suite tested nothing.
        .target(
            name: "DictionaryKitMCP",
            dependencies: [
                "DictionaryKit",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        // Like the MCP server, the command lives in a library so it can be tested; the
        // executable target below is a thin @main shim.
        .target(
            name: "DictionaryKitCLI",
            dependencies: [
                "DictionaryKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        // The binary is named by the product ("dictionarykit"); the target keeps a distinct
        // name because SwiftPM resolves target names case-insensitively on macOS, so a
        // target called "dictionarykit" would be ambiguous with the "DictionaryKit" library.
        .executableTarget(
            name: "dictionarykit-cli",
            dependencies: ["DictionaryKitCLI"]
        ),
        .executableTarget(
            name: "dictionarykit-mcp-server",
            dependencies: [
                "DictionaryKitMCP",
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(
            name: "DictionaryKitTests",
            dependencies: ["DictionaryKit"]
        ),
        .testTarget(
            name: "DictionaryKitMCPTests",
            dependencies: [
                "DictionaryKitMCP",
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .testTarget(
            name: "DictionaryKitCLITests",
            dependencies: [
                "DictionaryKitCLI",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        // Black-box tests: they spawn the built binary rather than importing it, because exit
        // codes and the stdout/stderr split are properties of a process and cannot be observed
        // from inside the module. The dependency on the executable target is what makes
        // `swift test` build the binary these tests need.
        .testTarget(
            name: "DictionaryKitCLIEndToEndTests",
            dependencies: ["dictionarykit-cli", "DictionaryKit"]
        )
    ]
)
