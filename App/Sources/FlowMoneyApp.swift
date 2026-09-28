import AppFeature
import BackgroundTasks
import SwiftUI

/// The app target is only this file: all product code lives in the FlowKit package.
@main
struct FlowMoneyApp: App {
    @State private var model = AppModel(environment: .live())
    @Environment(\.scenePhase) private var scenePhase

    nonisolated static let refreshTaskID = "com.lynkto.flowmoney.refresh"

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Self.scheduleRefresh()
            }
        }
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            Self.scheduleRefresh()
            await model.backgroundRefresh()
        }
    }

    /// Asks iOS to wake the app in a few hours to sync and post due bills. iOS decides the exact time.
    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
