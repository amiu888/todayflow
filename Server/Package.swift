// swift-tools-version: 6.0
// TodayFlow Sync Server — the central database every TodayFlow device syncs with.
// Stores rows generically (entity + id + JSON), so app schema changes need no
// server migration. Runs on macOS for development and Linux in Docker.
import PackageDescription

let package = Package(
    name: "TodayFlowServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.5.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0"),
    ],
    targets: [
        .target(
            name: "TodayFlowServerKit",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ],
            path: "Sources/TodayFlowServerKit"
        ),
        .executableTarget(
            name: "TodayFlowServer",
            dependencies: [
                "TodayFlowServerKit",
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            path: "Sources/TodayFlowServer"
        ),
        .testTarget(
            name: "TodayFlowServerTests",
            dependencies: [
                "TodayFlowServerKit",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/TodayFlowServerTests"
        ),
    ]
)
