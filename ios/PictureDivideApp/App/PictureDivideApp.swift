import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 后台扫描任务必须在启动早期注册。
        BackgroundSupport.registerBackgroundScan()
        return true
    }
}

@main
struct PictureDivideApp: App {
    @StateObject private var state = AppState()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .task {
                    await state.bootstrap()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // 回到前台：如果上次扫描被打断，自动接着跑。
                    if state.scanInterrupted && !state.progress.isRunning {
                        state.startScan()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: BackgroundSupport.backgroundScanNotification)) { _ in
                    // 系统在后台唤起扫描任务。
                    state.startScan()
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
