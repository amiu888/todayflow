// swift-tools-version: 6.0
import PackageDescription

// TodayFlow — native macOS daily task app.
//
// One Swift package, multiple library targets that map 1:1 onto the "packages"
// in driver.md §5 (Clean Architecture). Dependencies point at the core and never
// the other way around:
//
//   TodayFlowCore        — entities, use cases, ports (Foundation only)
//   TodayFlowPersistence — GRDB repositories, migrations, FTS, outbox
//   TodayFlowSync        — outbox + sync engine (Noop in v1)
//   TodayFlowRecognition — drop parsing pipeline
//   TodayFlowAI          — OpenAI-compatible client
//   TodayFlowDesign      — colors, icons, animations, shared components
//   TodayFlowFeatures    — SwiftUI features (Today, Capture, Detail, …)
//   TodayFlowMac         — app target: composition root, NSPanel, NSStatusItem
//
// Only the targets that exist so far are declared; each is added as its build
// increment lands (see driver.md §11 build order).

let package = Package(
    name: "TodayFlow",
    platforms: [
        .macOS(.v14),
        .iOS("26.0"), // the iPhone app (docs/ios/DESIGN.md §8)
        .watchOS(.v10),
    ],
    products: [
        .library(name: "TodayFlowCore", targets: ["TodayFlowCore"]),
        .library(name: "TodayFlowPersistence", targets: ["TodayFlowPersistence"]),
        .library(name: "TodayFlowSync", targets: ["TodayFlowSync"]),
        .library(name: "TodayFlowRecognition", targets: ["TodayFlowRecognition"]),
        .library(name: "TodayFlowAI", targets: ["TodayFlowAI"]),
        .library(name: "TodayFlowDesign", targets: ["TodayFlowDesign"]),
        .library(name: "TodayFlowFeatures", targets: ["TodayFlowFeatures"]),
        .library(name: "TodayFlowMac", targets: ["TodayFlowMac"]),
        .library(name: "TodayFlowPhone", targets: ["TodayFlowPhone"]),
        .executable(name: "TodayFlowApp", targets: ["TodayFlowApp"]),
    ],
    dependencies: [
        // driver.md §6: SQLite via GRDB (WAL, FTS5, versioned migrations).
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "TodayFlowCore",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "TodayFlowPersistence",
            dependencies: [
                "TodayFlowCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "TodayFlowSync",
            dependencies: ["TodayFlowCore", "TodayFlowPersistence"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "TodayFlowRecognition",
            dependencies: ["TodayFlowCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "TodayFlowAI",
            dependencies: ["TodayFlowCore"],
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "TodayFlowDesign",
            dependencies: ["TodayFlowCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "TodayFlowFeatures",
            dependencies: ["TodayFlowCore", "TodayFlowDesign", "TodayFlowRecognition"],
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TodayFlowFeaturesTests",
            dependencies: ["TodayFlowFeatures"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TodayFlowDesignTests",
            dependencies: ["TodayFlowDesign"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TodayFlowCoreTests",
            dependencies: ["TodayFlowCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TodayFlowSyncTests",
            dependencies: [
                "TodayFlowSync", "TodayFlowPersistence", "TodayFlowCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TodayFlowAITests",
            dependencies: ["TodayFlowAI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TodayFlowRecognitionTests",
            dependencies: ["TodayFlowRecognition"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TodayFlowPersistenceTests",
            dependencies: ["TodayFlowPersistence"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "TodayFlowMac",
            dependencies: [
                "TodayFlowCore",
                "TodayFlowPersistence",
                "TodayFlowSync",
                "TodayFlowRecognition",
                "TodayFlowAI",
                "TodayFlowDesign",
                "TodayFlowFeatures",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        // iPhone screens (docs/ios/DESIGN.md). Every file is `#if os(iOS)`, so
        // the Mac build compiles it to nothing; the app lives in iOS/project.yml.
        .target(
            name: "TodayFlowPhone",
            dependencies: [
                "TodayFlowCore",
                "TodayFlowPersistence",
                "TodayFlowSync",
                "TodayFlowRecognition",
                "TodayFlowDesign",
                "TodayFlowFeatures",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "TodayFlowApp",
            dependencies: ["TodayFlowMac"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "TodayFlowMacTests",
            dependencies: [
                "TodayFlowMac",
                "TodayFlowCore",
                "TodayFlowPersistence",
                "TodayFlowRecognition",
                "TodayFlowDesign",
                "TodayFlowFeatures",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
