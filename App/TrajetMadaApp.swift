import SwiftUI
import TrajetCore

@main
struct TrajetMadaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.log)
        }
    }
}
