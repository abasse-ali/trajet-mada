import SwiftUI
import TrajetCore

@main
struct TrajetMadaApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundCollect.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.log)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.scheduleBackgroundCollection()
            }
        }
    }
}
