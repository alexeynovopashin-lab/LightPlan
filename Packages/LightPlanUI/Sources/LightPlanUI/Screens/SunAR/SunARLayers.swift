import Foundation

/// Слои экрана AR снизу вверх (шаг 29.8в.5). Порядок слоёв — причина того, что стекло на телефоне 29.8в.4 было
/// «без искажений»: дугу гнуть было нечему (слои, которые гнут, лежали под ней, а над ней лежал налёт без
/// гиба). `SunARLayers.order` — то, в каком порядке `SunARScreen` их ставит; в отладочной сборке слой можно
/// выключить аргументом `-LPSunARLayers camera,arc,…` и снять кадр без него — так порядок меряется по пикселям
/// (`Tools/ar_arc_offset.py`), а не угадывается.
enum SunARLayers: String, CaseIterable {
    /// Системное превью камеры и слой Metal над ним: гнёт кадр под дисками, прозрачен вне их.
    case camera
    /// Полоса Млечного Пути и ядро.
    case milkyWay
    /// Звёзды, линии и названия созвездий (29.8в.13).
    case stars
    /// Горизонт, дуга солнца и луны, подписи часов, стороны света, восход и закат — одним холстом.
    case arc
    /// Линза: гнутая копия того, что под диском (небо без камеры, дуга, полоса).
    case lens
    /// Налёт, свет по кромке, контур и фаза луны.
    case paint
    /// Подпись выбранного момента.
    case labels

    /// Порядок снизу вверх.
    static let order: [SunARLayers] = [.camera, .milkyWay, .stars, .arc, .lens, .paint, .labels]

    /// Слой нарисован. В выпуске — всегда; в отладке — если не задан список `-LPSunARLayers`.
    static func shown(_ layer: SunARLayers) -> Bool {
        #if DEBUG
        if let list = UserDefaults.standard.string(forKey: "LPSunARLayers") {
            return list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(layer.rawValue)
        }
        #endif
        return true
    }
}
