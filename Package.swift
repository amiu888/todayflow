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
        .iOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "TodayFlowCore", targets: ["TodayFlowCore"]),
    ],
    dependencies: [
        // GRDB.swift is added when TodayFlowPersistence lands (driver.md §6).
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
        .testTarget(
            name: "TodayFlowCoreTests",
            dependencies: ["TodayFlowCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
