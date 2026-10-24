import Foundation
import LightPlanDomain
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Файл виджета в общей папке приложения и расширения (30б.1, `docs/30b_widget_cut.md` § «Data»).
///
/// Пишет `WidgetFeed` в `group.<адрес приложения>/widget.json` и просит виджет перерисоваться — только если файл
/// изменился. Папку даёт подпись (`Config/LightPlan-iOS.entitlements`); на Mac и в тестах без папки — `nil`.
@MainActor
final class WidgetShare {
    let url: URL
    private var last: Data?

    init(url: URL) {
        self.url = url
    }

    static func live(bundleID: String? = Bundle.main.bundleIdentifier) -> WidgetShare? {
        #if os(iOS)
        guard let id = bundleID,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetFeed.groupID(bundleID: id))
        else { return nil }
        return WidgetShare(url: dir.appendingPathComponent(WidgetFeed.fileName))
        #else
        return nil
        #endif
    }

    /// `true` — файл переписан и виджет позван (замер спайка: перерисовка в ту же секунду).
    @discardableResult
    func publish(_ feed: WidgetFeed) -> Bool {
        let data = feed.encoded()
        guard data != last else { return false }
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        last = data
        #if os(iOS) && canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return true
    }
}

extension AppModel {
    /// Место «Света» — виджету: при запуске (`live()`) и при каждой смене места (`placeChanged`).
    func publishWidget() {
        widgetShare?.publish(WidgetFeed(place: .init(name: light.locationName, place: place.place)))
    }
}
