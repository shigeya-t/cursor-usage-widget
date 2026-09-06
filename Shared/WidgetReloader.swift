import WidgetKit

enum WidgetKind {
    static let usage = "AIUsageWidget"
}

enum WidgetReloader {
    static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.usage)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
