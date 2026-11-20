import SwiftUI
import TrajetCore

struct RootView: View {
    @Environment(LogStore.self) private var log
    @State private var tab = LaunchOptions.tab

    var body: some View {
        TabView(selection: $tab) {
            SearchView()
                .tabItem {
                    Label { Text("Trajets") } icon: { Image("ui.route") }
                }
                .tag(0)
            LogView()
                .tabItem {
                    Label { Text("Journal") } icon: { Image("ui.log") }
                }
                .badge(log.errorCount > 0 ? Text("\(min(log.errorCount, 99))") : nil)
                .tag(1)
            SettingsView()
                .tabItem {
                    Label { Text("Réglages") } icon: { Image("ui.settings") }
                }
                .tag(2)
        }
    }
}
