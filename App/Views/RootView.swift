import SwiftUI
import TrajetCore

struct RootView: View {
    @Environment(LogStore.self) private var log

    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Label { Text("Trajets") } icon: { Image("ui.route") }
                }
            LogView()
                .tabItem {
                    Label { Text("Journal") } icon: { Image("ui.log") }
                }
                .badge(log.errorCount > 0 ? Text("\(min(log.errorCount, 99))") : nil)
            SettingsView()
                .tabItem {
                    Label { Text("Réglages") } icon: { Image("ui.settings") }
                }
        }
    }
}
