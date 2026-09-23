import SwiftUI

/// Поставщик холста (docs/17 § 10): оба делаются, выбор — в настройках.
/// Пока приложение бесплатное, главный — MapLibre (слово Алексея 20.09.2026).
public enum MapCanvasSource: String, Sendable, CaseIterable {
    case mapLibre, mapKit
}

/// Точка на холсте — только координаты: выше этого модуля ни MapLibre, ни
/// MapKit не видны, и прибор говорит с холстом широтой, долготой и крупностью.
public struct MapCanvasCenter: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Холст карты. Поворота и наклона нет, как у веба: прибор и есть карта, и
/// крутиться они должны одним куском (ротор — итерация 20б).
///
/// `zoom` — уровень веба (`MAP_Z = 14`, плитка 512): у MapLibre он тот же,
/// MapKit получает ширину кадра в метрах из него же. `focusShift` — сдвиг
/// центра камеры, как `setPadding` веба: центр карты стоит в середине
/// свободного окна между стёклами, а не в середине экрана. Положительный —
/// поле снизу (центр выше середины).
public struct MapCanvasView: View {
    let source: MapCanvasSource
    let center: MapCanvasCenter
    let zoom: Double
    let dark: Bool
    let focusShift: CGFloat
    let onMove: (MapCanvasCenter) -> Void

    public init(source: MapCanvasSource, center: MapCanvasCenter, zoom: Double, dark: Bool,
                focusShift: CGFloat = 0,
                onMove: @escaping (MapCanvasCenter) -> Void = { _ in }) {
        self.source = source
        self.center = center
        self.zoom = zoom
        self.dark = dark
        self.focusShift = focusShift
        self.onMove = onMove
    }

    public var body: some View {
        #if canImport(MapLibre)
        if source == .mapLibre {
            MapLibreCanvas(center: center, zoom: zoom, dark: dark, focusShift: focusShift, onMove: onMove)
        } else {
            MapKitCanvas(center: center, zoom: zoom, dark: dark, focusShift: focusShift, onMove: onMove)
        }
        #else
        // На Mac MapLibre нет (дистрибутив только для iOS) — MapKit.
        MapKitCanvas(center: center, zoom: zoom, dark: dark, focusShift: focusShift, onMove: onMove)
        #endif
    }

    /// Метров на точку экрана на уровне `zoom` у широты `latitude` — плитка
    /// 512, как у MapLibre и веба. Общая мера двух поставщиков.
    public static func metersPerPoint(zoom: Double, latitude: Double) -> Double {
        40_075_016.686 * cos(latitude * .pi / 180) / (512 * pow(2, zoom))
    }
}

/// Описание холста — снятое `make mapstyle` из `beta/mapstyle.js`.
enum MapStyle {
    static func url(dark: Bool) -> URL? {
        Bundle.module.url(forResource: dark ? "style_dark" : "style_light", withExtension: "json")
    }
}
