import SwiftUI

@main
@MainActor
struct DataMeterApp: App {
    @State private var engine = UsageEngine()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationManager.shared.setup()
    }

    var body: some Scene {
        let meter = engine
        WindowGroup {
            ContentView(engine: meter)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: meter.didBecomeActive()
            case .background: meter.didEnterBackground()
            default: break
            }
        }
        .backgroundTask(.appRefresh(UsageEngine.bgTaskID)) {
            await meter.refreshInBackground()
        }
    }
}
