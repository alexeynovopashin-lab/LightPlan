import Foundation
import LightPlanCore

/// «Свет сейчас» на большом виджете без идущей съёмки (30и.16). Слова Алексея 16.11: «Стрит не всегда планируют… на первом экране "Свет"
/// я нашёл нужную мне информацию, а именно оценку света "сейчас" и когда будет золотой час» (на снимке обведены «Условия · Мягкий свет»
/// и «до золотого часа 1 ч 13 м»). Правила — те же, что у экрана «Свет» (`LightTelemetry.build`): состояние `SolarDay.state(at:)`, закрытое
/// небо дня (`DayQuality.poor`) перебивает свет — «Небо закрыто», одно деление; отсчёт — `SolarDay.nextLight(at:)`, короткая длительность
/// `durS.*`. Чистая функция от `WidgetFrame`: виджет только рисует.
extension BigWidget {

    public struct LightNow: Equatable, Sendable {
        /// Деления прибора 1…5 (как строка «Условия» экрана «Свет»); `nil` — звёздный знак (ночь, астрономические сумерки).
        public var level: Int?
        public var tone: LightTone
        /// «Мягкий свет», «Небо закрыто»…
        public var text: String
        /// «До золотого часа», «До заката», «Золотой час, ещё»…
        public var nextLabel: String
        /// «1 ч 13 м»; `nil` — полярные сутки или ночь (подпись говорит сама).
        public var nextValue: String?
    }

    public static func lightNow(_ f: WidgetFrame) -> LightNow? {
        guard let place = f.place.place, let tz = f.place.timeZone else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: f.now)
        guard let y = c.year, let mo = c.month, let d = c.day, let h = c.hour, let mi = c.minute else { return nil }
        let sun = SolarDay(date: CivilDate(year: y, month: mo, day: d), place: place)
        let t = Double(h * 60 + mi) + Double(c.second ?? 0) / 60
        let raw = sun.state(at: t)
        // Экран «Свет»: плохая погода дня заменяет состояние целиком — нейтральный тон, одно деление, без звёзд.
        let poor = f.rating?.category == .poor
        let stars = poor ? false : raw.stars
        let text = poor ? f.words.extra("rec.overcast", "Небо закрыто") : f.words.extra("rec.\(raw.code.rawValue)", fallbackRec[raw.code] ?? "")
        let next = sun.nextLight(at: t)
        return LightNow(level: stars ? nil : (poor ? 1 : (raw.level ?? 1)), tone: poor ? .neutral : raw.tone, text: text,
                        nextLabel: f.words.extra("next.\(next.key.rawValue)", fallbackNext[next.key] ?? ""),
                        nextValue: next.minutes.map { shortSpan(f, minutes: $0) })
    }

    /// «1 ч 13 м» / «2 ч» / «40 мин» — `LightTelemetry.durShort` экрана «Свет» (шаблоны `durS.*` из словаря приложения).
    public static func shortSpan(_ f: WidgetFrame, minutes m: Minutes) -> String {
        let whole = max(0, Int(m.rounded()))
        if whole < 60 { return f.words.extra("durS.minutes", "{m} мин").replacingOccurrences(of: "{m}", with: "\(whole)") }
        let h = whole / 60, mm = whole % 60
        let template = mm != 0 ? f.words.extra("durS.hoursMins", "{h} ч {m} м") : f.words.extra("durS.hours", "{h} ч")
        return template.replacingOccurrences(of: "{h}", with: "\(h)").replacingOccurrences(of: "{m}", with: "\(mm)")
    }

    /// Ключи подписей отсчёта (`next.*` словаря): `NextLightKey` не перечисляем, список здесь — для приложения, которое кладёт слова в файл.
    public static let nextKeys: [NextLightKey] = [.polarDay, .polarNight, .toDawn, .goldenLeft, .toGolden, .toSunset, .blueLeft]

    static let fallbackRec: [LightCode: String] = [
        .noon: "Жёсткий свет", .morning: "Ровный свет", .day: "Ровный свет", .morningWarm: "Мягкий свет", .evening: "Мягкий свет",
        .golden: "Отличный свет", .dawn: "Отличный свет", .sunset: "Отличный свет", .dawning: "Мягкий свет", .dusk: "Мягкий свет",
        .blue: "Отличный свет", .deepDusk: "Слабый свет", .astroDawn: "Звёздное небо", .astroDusk: "Звёздное небо", .astroNight: "Звёздная ночь",
    ]

    static let fallbackNext: [NextLightKey: String] = [
        .polarDay: "Полярный день", .polarNight: "Полярная ночь", .toDawn: "До рассвета", .goldenLeft: "Золотой час, ещё",
        .toGolden: "До золотого часа", .toSunset: "До заката", .blueLeft: "Синий час, ещё",
    ]
}
