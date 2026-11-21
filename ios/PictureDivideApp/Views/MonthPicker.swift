import SwiftUI
import UIKit

/// 月份选择器（UIKit `UIDatePicker` 的 `.yearAndMonth` 模式）。
///
/// SwiftUI 的 `DatePicker` 只有 `.date` / `.hourAndMinute` 两种组件，没有"只选年月"，
/// 所以这里用 `UIViewRepresentable` 包一层 UIDatePicker，给出干净的年+月滚轮。
struct MonthPicker: UIViewRepresentable {
    @Binding var date: Date
    /// 可选范围（默认不早于 2000 年、不晚于今天）。
    var minimumDate: Date = Calendar.current.date(from: DateComponents(year: 2000)) ?? Date()
    var maximumDate: Date = Date()

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .yearAndMonth
        picker.preferredDatePickerStyle = .wheels
        picker.calendar = Calendar(identifier: .gregorian)
        picker.locale = Locale(identifier: "zh_CN")
        picker.minimumDate = minimumDate
        picker.maximumDate = maximumDate
        picker.date = date
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ picker: UIDatePicker, context: Context) {
        picker.minimumDate = minimumDate
        picker.maximumDate = maximumDate
        if abs(picker.date.timeIntervalSince(date)) > 1 {
            picker.date = date
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: MonthPicker
        init(_ parent: MonthPicker) { self.parent = parent }

        @objc func changed(_ sender: UIDatePicker) {
            parent.date = sender.date
        }
    }
}
