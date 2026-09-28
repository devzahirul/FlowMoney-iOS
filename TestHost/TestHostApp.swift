import SwiftUI

/// Empty app that hosts the unit-test bundle on a physical device (package test bundles can't run there on their
/// own). Keeping it separate from FlowMoney means the real app links FlowKit statically, exactly as it ships.
@main
struct TestHostApp: App {
    var body: some Scene {
        WindowGroup { Text("FlowKit unit tests") }
    }
}
