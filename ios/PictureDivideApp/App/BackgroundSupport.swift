import BackgroundTasks
import Foundation
import UIKit

/// 后台运行支持。
///
/// iOS 的现实是：**App 切后台/息屏后会被挂起**，没有"一直跑"这回事。
/// 我们用三层办法把扫描尽可能跑完：
/// 1. `beginBackgroundTask`：切后台或息屏时申请一段额外执行时间（通常几十秒到几分钟）。
/// 2. **断点续扫**：每扫完一批就把游标（最后扫到的照片时间）写进 UserDefaults，
///    被系统杀掉后下次打开从断点继续，不会白扫。
/// 3. `BGProcessingTask`：让系统在合适时机（充电/空闲）帮我们跑后台扫描任务。
enum BackgroundSupport {
    /// BGTask 的标识，需要和 Info.plist 里的 BGTaskSchedulerPermittedIdentifiers 一致。
    static let taskIdentifier = "com.picturedivide.personal.scan"

    private static var taskID: UIBackgroundTaskIdentifier = .invalid

    /// 申请一段后台执行时间。
    static func beginBackgroundTask(expiration: @escaping () -> Void) {
        guard taskID == .invalid else { return }
        taskID = UIApplication.shared.beginBackgroundTask(withName: "PictureDivideScan") {
            // 系统要收回时间了：通知扫描中止（会保存游标），然后结束任务。
            expiration()
            BackgroundSupport.endBackgroundTask()
        }
    }

    static func endBackgroundTask() {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }

    /// 后台扫描被系统唤起时发的通知。
    static let backgroundScanNotification = Notification.Name("com.picturedivide.backgroundScan")

    /// 注册后台扫描任务（必须在 App 启动早期调用）。
    static func registerBackgroundScan() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            NotificationCenter.default.post(name: backgroundScanNotification, object: nil)
            task.setTaskCompleted(success: true)
        }
    }

    /// 申请一次后台扫描任务。
    static func scheduleBackgroundScan(after seconds: TimeInterval = 15 * 60) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            NSLog("[PictureDivide] 提交后台任务失败：%@", error.localizedDescription)
        }
    }
}

/// 扫描游标：记住上次扫到哪里，支持断点续扫。
struct ScanCursor: Codable {
    var lastDate: Date?
    var lastIdentifier: String?

    static let defaultsKey = "com.picturedivide.scanCursor"

    static func load() -> ScanCursor {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let cursor = try? JSONDecoder().decode(ScanCursor.self, from: data) else {
            return ScanCursor()
        }
        return cursor
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
