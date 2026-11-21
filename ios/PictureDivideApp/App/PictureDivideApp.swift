import SwiftUI

@main
struct PictureDivideApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .task {
                    await state.bootstrap()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ScanView()
                .tabItem { Label("扫描", systemImage: "magnifyingglass") }
                .tag(0)

            ReviewView()
                .tabItem { Label("复核", systemImage: "exclamationmark.bubble") }
                .badge(state.flagged.filter { $0.state == .pending }.count)
                .tag(1)

            VaultView()
                .tabItem { Label("保险箱", systemImage: "lock.shield") }
                .tag(2)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(3)
        }
    }
}
