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

/// Камера холста на кадре: центр, крупность (уровень веба, плитка 512) и
/// кто двигает — палец или программа. Булавки сохранённых точек едут по ней
/// на каждом кадре жеста (итерация 20б); `byHand` закрывает полосу точки
/// (`move` с `originalEvent` у веба).
public struct MapCanvasCamera: Equatable, Sendable {
    public var center: MapCanvasCenter
    public var zoom: Double
    public var byHand: Bool
    public init(center: MapCanvasCenter, zoom: Double, byHand: Bool = false) {
        self.center = center
        self.zoom = zoom
        self.byHand = byHand
    }
}

/// Холст карты. Поворота и наклона нет, как у веба: прибор и есть карта, и
/// крутиться они должны одним куском (ротор — итерация 20б).
///
/// `zoom` — уровень веба (`MAP_Z = 14`, плитка 512): у MapLibre он тот же,
/// MapKit получает ширину кадра в метрах из него же. `focusShift` — сдвиг
/// центра камеры, как `setPadding` веба: центр карты стоит в середине
/// свободного окна между стёклами, а не в середине экрана. Положительный —
/// поле снизу (центр выше середины). `focusGlide` — сдвиг меняется плавно
/// (`easeTo` веба, 0,3 с): низ убрали или вернули, головка едет следом.
/// Что холсту делать с молчащей CARTO: сторож и два слова наружу — плитка пришла, плитки нет.
public struct MapCanvasFallback {
    public var timeout: Duration
    public var onTile: @MainActor () -> Void
    public var onSilent: @MainActor () -> Void
    public init(timeout: Duration = MapFallbackGate.timeout, onTile: @escaping @MainActor () -> Void, onSilent: @escaping @MainActor () -> Void) {
        self.timeout = timeout
        self.onTile = onTile
        self.onSilent = onSilent
    }
}

public struct MapCanvasView: View {
    let source: MapCanvasSource
    let center: MapCanvasCenter
    let zoom: Double
    let dark: Bool
    let labels: Bool
    let language: String
    let panEnabled: Bool
    let focusShift: CGFloat
    let focusGlide: Bool
    let onMove: (MapCanvasCenter) -> Void
    let onCamera: (MapCanvasCamera) -> Void
    /// Тап по холсту, палец не поехал (`click` движка веба) — точка в
    /// собственных координатах холста, без поворота ротора.
    let onTap: (CGPoint) -> Void
    /// Сторож первой плитки CARTO (28л.3): `nil` — не следить (выбор холста сделан руками или CARTO уже ответила).
    let fallback: MapCanvasFallback?

    /// `labels` — подписи улиц и мест (тумблер настроек, у веба
    /// `mapLabels`); только у MapLibre: MapKit их не выключает.
    public init(source: MapCanvasSource, center: MapCanvasCenter, zoom: Double, dark: Bool,
                labels: Bool = false, language: String = "en", panEnabled: Bool = true, focusShift: CGFloat = 0,
                focusGlide: Bool = false,
                onMove: @escaping (MapCanvasCenter) -> Void = { _ in },
                onCamera: @escaping (MapCanvasCamera) -> Void = { _ in },
                onTap: @escaping (CGPoint) -> Void = { _ in },
                fallback: MapCanvasFallback? = nil) {
        self.fallback = fallback
        self.source = source
        self.center = center
        self.zoom = zoom
        self.dark = dark
        self.labels = labels
        self.language = language
        self.panEnabled = panEnabled
        self.focusShift = focusShift
        self.focusGlide = focusGlide
        self.onMove = onMove
        self.onCamera = onCamera
        self.onTap = onTap
    }

    public var body: some View {
        #if canImport(MapLibre)
        if source == .mapLibre {
            MapLibreCanvas(center: center, zoom: zoom, style: MapStyle.url(dark: dark, labels: labels, language: language),
                           panEnabled: panEnabled, focusShift: focusShift, focusGlide: focusGlide, onMove: onMove,
                           onCamera: onCamera, onTap: onTap, fallback: fallback)
        } else {
            MapKitCanvas(center: center, zoom: zoom, dark: dark, panEnabled: panEnabled, focusShift: focusShift, onMove: onMove,
                           onCamera: onCamera, onTap: onTap)
        }
        #else
        // На Mac MapLibre нет (дистрибутив только для iOS) — MapKit.
        MapKitCanvas(center: center, zoom: zoom, dark: dark, panEnabled: panEnabled, focusShift: focusShift, onMove: onMove,
                           onCamera: onCamera, onTap: onTap)
        #endif
    }

    /// Метров на точку экрана на уровне `zoom` у широты `latitude` — плитка
    /// 512, как у MapLibre и веба. Общая мера двух поставщиков.
    public static func metersPerPoint(zoom: Double, latitude: Double) -> Double {
        40_075_016.686 * cos(latitude * .pi / 180) / (512 * pow(2, zoom))
    }
}

/// Описание холста — снятое `make mapstyle` из `beta/mapstyle.js` с
/// выключенными подписями. Включённые — тот же стиль, у которого символьные
/// слои видны и пишут имя на языке приложения (`build({labels, lang})` веба):
/// файл собирается один раз на тему и язык и лежит в кэше.
public enum MapStyle {
    nonisolated(unsafe) private static var built: Set<URL> = []
    static func url(dark: Bool, labels: Bool = false, language: String = "en", cartoKey: String? = CartoKey.current) -> URL? {
        let base = Bundle.module.url(forResource: dark ? "style_dark" : "style_light", withExtension: "json")
        #if DEBUG
        let silent = UserDefaults.standard.bool(forKey: "LPCartoSilent")
        #else
        let silent = false
        #endif
        guard labels || cartoKey != nil || silent, let base else { return base }
        let key = nameKey(language)
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("lp_style_\(dark ? "dark" : "light")_\(key.replacingOccurrences(of: ":", with: "_"))\(labels ? "_l" : "")\(cartoKey != nil ? "_k" : "")\(silent ? "_s" : "").json")
        // Раз за запуск: файл прошлой сборки мог остаться от старого стиля.
        if built.contains(out) { return out }
        guard var data = try? Data(contentsOf: base) else { return base }
        if labels { guard let p = patch(data, labels: true, key: key) else { return base }; data = p }
        if let cartoKey { guard let k = keyed(data, key: cartoKey) else { return base }; data = k }
        #if DEBUG
        // Прибор 28л.3: плитки уходят на закрытый порт — источник, который заведомо не ответит.
        if silent, let s = String(data: data, encoding: .utf8) {
            data = Data(s.replacingOccurrences(of: "basemaps.cartocdn.com", with: "127.0.0.1:9").utf8)
        }
        #endif
        guard (try? data.write(to: out, options: .atomic)) != nil else { return base }
        built.insert(out)
        return out
    }

    /// Ключ CARTO в адресах плиток и шрифтов стиля (`?key=…`, документация CARTO Basemaps). Спрайт не
    /// трогаем: движок дописывает к нему `.json` и `@2x.png`, и после `?key=…` имя файла ломается (замер:
    /// 404); ключа он и не требует. Адреса не CARTO остаются как были.
    public static func keyed(_ data: Data, key: String) -> Data? {
        guard var style = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#")
        guard let q = key.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        func add(_ url: String) -> String {
            guard url.contains("basemaps.cartocdn.com") else { return url }
            return url + (url.contains("?") ? "&" : "?") + "key=" + q
        }
        if let glyphs = style["glyphs"] as? String { style["glyphs"] = add(glyphs) }
        if var sources = style["sources"] as? [String: Any] {
            for (name, value) in sources {
                guard var src = value as? [String: Any] else { continue }
                if let tiles = src["tiles"] as? [String] { src["tiles"] = tiles.map(add) }
                sources[name] = src
            }
            style["sources"] = sources
        }
        return try? JSONSerialization.data(withJSONObject: style)
    }

    /// `nameKey` веба: плитка несёт ru, en, zh, ja; остальное — английский.
    public static func nameKey(_ code: String) -> String {
        switch code.split(separator: "-").first.map(String.init) ?? "" {
        case "ru": "name:ru"
        case "zh": "name:zh"
        case "ja": "name:ja"
        default: "name:en"
        }
    }

    /// Символьные слои: видимость по тумблеру, имя — `coalesce(key, name)`:
    /// нет перевода — то, что написано на доме.
    public static func patch(_ data: Data, labels: Bool, key: String) -> Data? {
        guard var style = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let layers = style["layers"] as? [[String: Any]] else { return nil }
        style["layers"] = layers.map { l -> [String: Any] in
            guard l["type"] as? String == "symbol" else { return l }
            var l = l
            var layout = l["layout"] as? [String: Any] ?? [:]
            if layout["text-field"] != nil {
                layout["text-field"] = ["coalesce", ["get", key], ["get", "name"]] as [Any]
            }
            layout["visibility"] = labels ? "visible" : "none"
            l["layout"] = layout
            return l
        }
        return try? JSONSerialization.data(withJSONObject: style)
    }
}
