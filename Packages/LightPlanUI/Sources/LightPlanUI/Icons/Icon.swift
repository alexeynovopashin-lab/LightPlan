import SwiftUI

/// Знак из библиотеки Light Plan — `IC.svg(...)` веба.
///
/// Библиотека — 208 контурных знаков на холсте 24×24, генерируется из
/// `beta/icons.js` (`Tools/icons2assets.js`). SF Symbols её не заменяют и с ней
/// не смешиваются.
///
/// Как и в вебе, размер, толщина линии и цвет задаются снаружи, а не в знаке:
/// - `size` — сторона квадрата в pt;
/// - `line` — толщина в единицах холста 24×24, то есть на 22 pt при `line: 1.5`
///   линия 1,375 pt — так рисует лист знаков веба; веб-контексты берут
///   от 1,4 до 2,4;
/// - цвет — `.foregroundStyle(...)`; погода красит части врозь через `partStyles`.
public struct Icon: View {

    /// Часть погоды, которую можно красить отдельно.
    public enum Part: Sendable, Hashable { case sun, cloud, rain }

    let art: IconArt
    let size: CGFloat
    let line: CGFloat
    let partStyles: [Part: AnyShapeStyle]

    /// Знак по имени. Имя, которого нет, — нейтральный кружок: отсутствие знака
    /// не ломает разметку (так же, как `ICONS.body` в вебе).
    public init(_ name: String, size: CGFloat = 22, line: CGFloat = 1.5, partStyles: [Part: AnyShapeStyle] = [:]) {
        self.init(art: Icon.common(name), size: size, line: line, partStyles: partStyles)
    }

    /// Знак жанра съёмки по коду (`ICONS.genre`). Неизвестный код — камера.
    public init(genre code: String, size: CGFloat = 22, line: CGFloat = 1.5) {
        let art = IconArt.art(namespace: "genres", name: code, in: IconLibrary.genres) ?? Icon.common("camera")
        self.init(art: art, size: size, line: line, partStyles: [:])
    }

    /// Знак пожелания к погоде по коду (`ICONS.wishes`). Своё пространство имён:
    /// `rain` пожелания — не то же самое, что `rain` погоды.
    public init(wish code: String, size: CGFloat = 22, line: CGFloat = 1.5) {
        let art = IconArt.art(namespace: "wishes", name: code, in: IconLibrary.wishes) ?? Icon.common("dot")
        self.init(art: art, size: size, line: line, partStyles: [:])
    }

    /// Знак точки дня по её названию, месту и ссылке на студию (`ICONS.forPoint`).
    public init(point title: String, place: String? = nil, studio: Bool = false, size: CGFloat = 22, line: CGFloat = 1.5) {
        self.init(PointSign.name(for: title, place: place, studio: studio), size: size, line: line)
    }

    init(art: IconArt, size: CGFloat, line: CGFloat, partStyles: [Part: AnyShapeStyle]) {
        self.art = art
        self.size = size
        self.line = line
        self.partStyles = partStyles
    }

    static func common(_ name: String) -> IconArt {
        IconArt.art(namespace: "common", name: name, in: IconLibrary.common)
            ?? IconArt.art(namespace: "common", name: "dot", in: IconLibrary.common)!
    }

    public var body: some View {
        let k = size / 24
        ZStack {
            ForEach(art.parts.indices, id: \.self) { i in
                let part = art.parts[i]
                let stroke = StrokeStyle(lineWidth: (part.width ?? line) * k,
                                         lineCap: part.butt ? .butt : .round,
                                         lineJoin: .round)
                // Без своего цвета часть берёт цвет окружения (`.foregroundStyle` снаружи).
                // Подставлять сюда `.foreground` нельзя: он разрешается в `.primary`
                // (чёрный при 85 %) и перекрывает то, что задал вызывающий.
                if let own = ownStyle(for: part.role) {
                    IconOutline(path: part.path).stroke(own, style: stroke)
                } else {
                    IconOutline(path: part.path).stroke(style: stroke)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func ownStyle(for role: IconArt.Role) -> AnyShapeStyle? {
        switch role {
        case .body: nil
        case .sun: partStyles[.sun]
        case .cloud: partStyles[.cloud]
        case .rain: partStyles[.rain]
        }
    }
}

/// Контур части знака: путь на холсте 24×24, растянутый на весь прямоугольник.
struct IconOutline: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(scaleX: k, y: k))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
