import Foundation

/// Папки набора референсов (веб `GENRE_TAGS`, `TAG_CODE`, `refTagsFor`):
/// чипы полного экрана — только использованные папки, сперва из списка жанра,
/// потом чужие слова с кадров.
public enum RefFolders {
    /// Русское имя папки → код (веб `TAG_CODE`); свои слова проходят как есть.
    public static let tagCode: [String: String] = [
        "Сборы": "gathering", "Пара": "couple", "Невеста": "bride", "Жених": "groom",
        "Прогулка": "walk", "Вечер": "evening", "Детали": "details",
        "Виновник": "celebrant", "Гости": "guests", "Стол": "table", "Танцы": "dancing",
        "Все вместе": "allTogether", "Дети": "kids", "Родители": "parents", "Игра": "play",
        "Лицо": "face", "В рост": "fullLength", "Руки": "hands", "Свет": "light",
        "Предмет": "object", "Ракурсы": "angles", "Фактура": "texture", "Композиция": "composition",
        "Кампания": "campaign", "Модель": "model", "Продукт": "product", "Сцена": "scene",
        "Фасад": "facade", "Интерьер": "interior", "Деталь": "detail", "Общий план": "wideShot",
        "Герой": "hero", "Общий": "wide", "Крупный": "closeUp", "Момент": "moment",
        "Передний план": "foreground", "Небо": "sky", "Кадр": "frame", "Геометрия": "geometry"
    ]

    public static let genreTags: [String: [String]] = [
        "wedding": ["gathering", "couple", "bride", "groom", "walk", "evening", "details"],
        "party": ["celebrant", "guests", "table", "dancing", "details"],
        "lovestory": ["couple", "walk", "evening", "details"],
        "family": ["allTogether", "kids", "parents", "play", "details"],
        "portrait": ["face", "fullLength", "hands", "light", "details"],
        "animals": ["face", "fullLength", "play", "light", "details"],
        "product": ["object", "angles", "texture", "composition"],
        "ad": ["campaign", "model", "product", "scene"],
        "architecture": ["facade", "interior", "detail", "wideShot"],
        "report": ["hero", "wide", "closeUp", "moment"],
        "landscape": ["wide", "foreground", "sky", "light"],
        "street": ["frame", "hero", "light", "geometry"]
    ]
    public static let defaultTags = ["wide", "closeUp", "light", "details"]

    public static func code(_ tag: String) -> String { tagCode[tag] ?? tag }

    /// Все коды разделов, какие знает приложение (веб `allTagCodes`): по ним сверяют набранное.
    public static var allCodes: [String] {
        var out: [String] = [], seen = Set<String>()
        for g in genreTags.keys.sorted() { for c in genreTags[g]! where seen.insert(c).inserted { out.append(c) } }
        for c in defaultTags where seen.insert(c).inserted { out.append(c) }
        return out
    }

    /// Слово, набранное руками, — известный код, если совпало без учёта регистра с русским именем, кодом
    /// или названием на нынешнем языке; иначе слово проходит строчным (веб `tagCanon`).
    public static func canon(_ word: String, tagName: (String) -> String) -> String {
        let w = word.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return "" }
        let low = w.lowercased()
        if let ru = tagCode.first(where: { $0.key.lowercased() == low }) { return ru.value }
        for c in allCodes where c.lowercased() == low || tagName(c).lowercased() == low { return c }
        return low
    }

    /// Папки, в которых есть кадры: сперва из списка жанра (в его порядке),
    /// потом остальные — в порядке первой встречи.
    public static func used(in frames: [RefFrame], genre: String?) -> [String] {
        let present = frames.flatMap { $0.tags.map(code) }
        var seen = Set<String>(), out: [String] = []
        for c in genreTags[genre ?? ""] ?? defaultTags where present.contains(c) && seen.insert(c).inserted { out.append(c) }
        for c in present where seen.insert(c).inserted { out.append(c) }
        return out
    }
}

/// Два раздела сетки — «Эта съёмка» и «Набор жанра» — с фильтром по папке
/// (веб `renderRefsFull`). Пустой раздел не рисуется.
public struct RefSections: Equatable, Sendable {
    public var own: [RefFrame]
    public var set: [RefFrame]

    public init(frames: [RefFrame], tag: String?) {
        let kept = tag.map { t in frames.filter { $0.tags.contains { RefFolders.code($0) == t } } } ?? frames
        own = kept.filter(\.own)
        set = kept.filter { !$0.own }
    }

    /// В порядке экрана: свои, потом набор.
    public var flat: [RefFrame] { own + set }
    /// Список просмотрщика — только картинки, в том порядке, что на экране.
    public var viewable: [RefFrame] { flat.filter(\.isViewable) }
    public var isEmpty: Bool { own.isEmpty && set.isEmpty }
}

/// Листание просмотрщика (веб `#refView`): по кругу, счётчик «3 / 12» при двух
/// кадрах и больше; числа — справка 27, раздел 4.
public struct RefPager: Equatable, Sendable {
    public let count: Int
    public private(set) var index: Int

    /// Сдвиг кадра, с которого листается (палец ≈ 67 pt: кадр идёт за пальцем ×0,9).
    public static let pageShift: Double = 60
    /// Сдвиг кадра вниз, с которого закрывается (палец ≈ 122 pt).
    public static let closeShift: Double = 110
    public static let zoomMax: Double = 6

    public init(count: Int, start: Int) {
        self.count = max(0, count)
        index = self.count == 0 ? 0 : min(max(0, start), self.count - 1)
    }

    public mutating func next() { if count > 1 { index = (index + 1) % count } }
    public mutating func previous() { if count > 1 { index = (index + count - 1) % count } }

    public var counter: String? { count >= 2 ? "\(index + 1) / \(count)" : nil }

    public enum Swipe: Equatable, Sendable { case next, previous, close, stay }

    /// Что делает жест целого кадра по сдвигу кадра `(dx, dy)`: побеждает та
    /// ось, где сдвиг больше; влево — следующий, вправо — предыдущий.
    public static func decide(dx: Double, dy: Double) -> Swipe {
        if abs(dy) > abs(dx) { return dy >= closeShift ? .close : .stay }
        if dx <= -pageShift { return .next }
        if dx >= pageShift { return .previous }
        return .stay
    }

    public mutating func apply(_ s: Swipe) -> Bool {
        switch s {
        case .next: next(); return true
        case .previous: previous(); return true
        case .close, .stay: return false
        }
    }

    /// Касание без движения — «лестница выхода»: увеличено → сброс до целого,
    /// целый → закрыть.
    public static func tap(scale: Double) -> Swipe { scale > 1.001 ? .stay : .close }
    public static func clampZoom(_ s: Double) -> Double { min(max(s, 1), zoomMax) }
}

/// Прямоугольник на экране в pt (Domain не знает CoreGraphics).
public struct RefBox: Equatable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
}

/// Куда летит кадр при закрытии (веб `rvHomeTransform`): в плитку кадра, на
/// котором остановились; ушла за край больше чем на 40 pt — уменьшается на месте.
public enum RefHome {
    public static let edgeSlack: Double = 40

    public static func target(tile: RefBox?, viewport: RefBox) -> RefBox? {
        guard let t = tile else { return nil }
        let s = edgeSlack
        if t.y + t.h < viewport.y - s || t.y > viewport.y + viewport.h + s
            || t.x + t.w < viewport.x - s || t.x > viewport.x + viewport.w + s { return nil }
        return t
    }

    /// Где кадр сейчас: открытым — вписан в экран; закрывается в плитку — на
    /// плитке; плитка за краем — остаётся на месте (уменьшается и гаснет, не
    /// летит к плитке, которой не видно); до раскрытия — на плитке открытия.
    public static func rect(open: Bool, shrinkingInPlace: Bool, home: RefBox?, start: RefBox?, fit: RefBox) -> RefBox {
        if shrinkingInPlace { return fit }
        return open ? fit : (home ?? start ?? fit)
    }
}

/// Две колонки сетки (`column-count: 2`): кадры идут по порядку, первая колонка
/// заполняется сверху вниз, вторая — следом; граница — где высоты ближе всего.
public enum RefColumns {
    /// `heights` — высоты плиток при одной ширине; ответ — сколько плиток в первой колонке.
    public static func firstColumnCount(heights: [Double]) -> Int {
        var best = 0, bestGap = Double.infinity
        let total = heights.reduce(0, +)
        var acc = 0.0
        for n in 0...heights.count {
            if n > 0 { acc += heights[n - 1] }
            let gap = abs(acc - (total - acc))
            if gap < bestGap { bestGap = gap; best = n }
        }
        return best
    }

    /// Высота плитки по пропорциям кадра; размеров нет — 4:3.
    public static func height(w: Double?, h: Double?, width: Double) -> Double {
        guard let w, let h, w > 0, h > 0 else { return width * 0.75 }
        return width * h / w
    }
}

/// Ссылка без картинки — плитка-надпись (веб `refHost`, `refTail`).
public enum RefLink {
    public static func host(_ url: String) -> String? {
        guard let h = URL(string: url)?.host, !h.isEmpty else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
    public static func tail(_ url: String) -> String {
        guard let u = URL(string: url), let host = u.host else { return String(url.prefix(42)) }
        let p = u.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return p.isEmpty ? host : String(p.prefix(42))
    }
}

/// Строка тегов внизу просмотрщика (веб `renderRvBars`): теги кадра; там, где их можно править
/// (папка мудборда), она нажимается, а у кадра без тегов стоит «+ тег» — иначе нажимать было бы не
/// на что. Где править нельзя, остаётся подписью, и пустая строка не рисуется.
public enum RefViewerTags {
    public enum Chip: Equatable, Sendable {
        case tag(String)
        case add
    }

    public static func chips(_ tags: [String], editable: Bool) -> [Chip] {
        if !tags.isEmpty { return tags.map(Chip.tag) }
        return editable ? [.add] : []
    }
}
