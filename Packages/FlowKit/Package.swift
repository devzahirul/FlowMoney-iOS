// swift-tools-version: 6.0
//
// FlowKit — every line of product code lives here. The app target is a thin shell.
//
// Layering (arrows = "depends on"; nothing points upward, features never import each other):
//
//   AppFeature ─┬─► *Feature ─► LedgerUI ─► DesignSystem ─► Domain ─► FlowCore
//               │                  └──────► Routing ──────► Domain
//               ├─► LedgerData ─────────────────────────────► Domain
//               └─► SupabaseBackend ─► LedgerData, Domain, supabase-swift (Auth + PostgREST only)
//
// `Domain` is pure Swift (no SwiftUI, no networking) — every business rule is unit-tested there.
// `SupabaseBackend` is the only module that knows Supabase exists; swapping the backend touches one module.

import PackageDescription

let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    // Zero-warning policy for our code only (third-party packages keep their own settings).
    .unsafeFlags(["-warnings-as-errors"]),
]

extension Target {
    static func module(
        _ name: String,
        dependencies: [Target.Dependency] = [],
        resources: [Resource]? = nil
    ) -> Target {
        .target(name: name, dependencies: dependencies, resources: resources, swiftSettings: strictSettings)
    }

    static func feature(_ name: String) -> Target {
        .module(name, dependencies: ["FlowCore", "Domain", "DesignSystem", "LedgerUI", "Routing"])
    }

    static func tests(_ name: String, dependencies: [Target.Dependency]) -> Target {
        .testTarget(name: name, dependencies: dependencies + ["TestSupport"], swiftSettings: strictSettings)
    }
}

let package = Package(
    name: "FlowKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"]),
        // Exposed so the app-hosted test bundle (which runs on a physical iPhone) can link them.
        .library(name: "FlowKitTesting", targets: [
            "FlowCore", "Domain", "LedgerData", "SupabaseBackend", "DesignSystem", "Routing", "LedgerUI",
            "AuthFeature", "HomeFeature", "ActivityFeature", "AccountsFeature", "PlanFeature",
            "InsightsFeature", "ProfileFeature", "AppFeature", "TestSupport",
        ]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.55.0"),
    ],
    targets: [
        // MARK: Core layers

        .module("FlowCore"),
        .module("Domain", dependencies: ["FlowCore"]),
        .module("LedgerData", dependencies: ["Domain", "FlowCore"]),
        .module("SupabaseBackend", dependencies: [
            "Domain", "FlowCore", "LedgerData",
            .product(name: "Auth", package: "supabase-swift"),
            .product(name: "PostgREST", package: "supabase-swift"),
        ]),

        // MARK: UI foundation

        .module("DesignSystem", dependencies: ["Domain", "FlowCore"]),
        .module("Routing", dependencies: ["Domain"]),
        .module("LedgerUI", dependencies: ["Domain", "FlowCore", "DesignSystem", "Routing"]),

        // MARK: Features

        .feature("AuthFeature"),
        .feature("HomeFeature"),
        .feature("ActivityFeature"),
        .feature("AccountsFeature"),
        .feature("PlanFeature"),
        .feature("InsightsFeature"),
        .feature("ProfileFeature"),

        // MARK: Composition root

        .module("AppFeature", dependencies: [
            "FlowCore", "Domain", "LedgerData", "SupabaseBackend", "DesignSystem", "Routing", "LedgerUI",
            "AuthFeature", "HomeFeature", "ActivityFeature", "AccountsFeature",
            "PlanFeature", "InsightsFeature", "ProfileFeature",
        ]),

        // MARK: Test support (fakes, builders, fixed clock) — linked by tests only

        .module("TestSupport", dependencies: ["Domain", "FlowCore", "LedgerData"]),

        // MARK: Tests

        .tests("FlowCoreTests", dependencies: ["FlowCore"]),
        .tests("DomainTests", dependencies: ["Domain", "FlowCore"]),
        .tests("LedgerDataTests", dependencies: ["LedgerData", "Domain", "FlowCore"]),
        .tests("SupabaseBackendTests", dependencies: ["SupabaseBackend", "Domain", "FlowCore"]),
        .tests("FeatureTests", dependencies: [
            "Domain", "FlowCore", "LedgerUI", "Routing",
            "AuthFeature", "HomeFeature", "ActivityFeature", "AccountsFeature",
            "PlanFeature", "InsightsFeature", "ProfileFeature", "AppFeature",
        ]),
    ]
)
