import Foundation
import LightPlanCore

/// Правила большого виджета (30и.13, вариант Б2): небо купола (слово света, Солнце и Луна, в том числе ушедшие под горизонт), оценка
/// рассвета и заката словом и числом, «через N» у съёмок. Чистые функции от `WidgetFrame` — виджет только рисует.
public enum BigWidget {

    // MARK: Небо

    /// Что на небе в момент `frame.now` по часам места: код состояния света (слово «Ночь», «Вечереет»…), высота Солнца и Луны, фаза Луны.
    public struct Sky: Equatable, Sendable {
        public var code: LightCode
        public var sunElevation: Degrees
        public var moonAltitude: Degrees
        public var moonAzimuth: Degrees
        /// Освещённая доля диска 0…1 и растёт ли она (до полнолуния).
        public var moonFraction: Double
        public var moonWaxing: Bool
        /// Восход завтрашнего дня, если известен: на ночной дорожке под куполом Солнце идёт к нему.
        public var nextRise: Date?
        /// Положение Луны в цикле 0…1 (0 — новолуние, 0,5 — полнолуние): по нему малый виджет ставит Луну в окне, как часы (30и.15).
        public var moonCycle: Double = 0
    }

    /// `nil` — у места нет координат/зоны (файл старого вида): купол рисуется без Луны, слово света берётся запасное.
    public static func sky(_ f: WidgetFrame) -> Sky? {
        guard let place = f.place.place, let tz = f.place.timeZone else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: f.now)
        guard let y = c.year, let mo = c.month, let d = c.day, let h = c.hour, let mi = c.minute else { return nil }
        let day = CivilDate(year: y, month: mo, day: d)
        let minutes = Double(h * 60 + mi)
        let sun = SolarDay(date: day, place: place)
        let e = sun.elevation(at: minutes)
        // «Утро» — до середины между восходом и закатом; полярные сутки: до полудня по часам.
        let morning: Bool
        if let r = f.day?.sunrise, let s = f.day?.sunset { morning = f.now < Date(timeIntervalSince1970: (r.timeIntervalSince1970 + s.timeIntervalSince1970) / 2) } else { morning = minutes < 720 }
        let moon = MoonSample(date: day, minutes: minutes, place: place, time: .iau)
        let phase = moon.phase
        return Sky(code: LightState(elevation: e, morning: morning).code, sunElevation: e,
                   moonAltitude: moon.altitude, moonAzimuth: moon.azimuth,
                   moonFraction: phase.fraction, moonWaxing: phase.cycle < 0.5,
                   nextRise: f.tomorrow?.sunrise, moonCycle: phase.cycle)
    }

    /// Слово света под временем на куполе (заглавными): «НОЧЬ», «ВЕЧЕРЕЕТ»… Слова — словарь приложения (`sun.<code>.label`), запасные русские.
    public static func phaseWord(_ code: LightCode, _ w: WidgetFeed.Words) -> String {
        w.extra("phase.\(code.rawValue)", fallbackPhase[code] ?? code.rawValue).uppercased()
    }

    static let fallbackPhase: [LightCode: String] = [
        .noon: "Полдень", .morning: "Утро", .day: "День", .morningWarm: "Тёплое утро", .evening: "Вечереет", .golden: "Золотой час",
        .dawn: "Рассвет", .sunset: "Закат", .dawning: "Светает", .dusk: "Сумерки", .blue: "Синий час", .deepDusk: "Глубокие сумерки",
        .astroDawn: "Глубокие сумерки", .astroDusk: "Глубокие сумерки", .astroNight: "Ночь",
    ]

    /// Плотность просвечивающего пятна ушедшего светила по высоте `e` — как `DomeGeometry.deepOf` приложения (пол 2/3, ниже −3° гаснет полностью).
    public static func ghostOpacity(elevation e: Degrees) -> Double {
        func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
        return clamp(-e / 3) * max(2.0 / 3.0, clamp((12 + e) / 9))
    }

    // MARK: Оценка

    /// Слово оценки как в приложении (`LightTelemetry.sunsetWord`, пороги 75 / 50 / 28).
    public static func scoreWord(_ s: Int, _ w: WidgetFeed.Words) -> String {
        s >= 75 ? w.extra("score.beautiful", "красивый") : s >= 50 ? w.extra("score.color", "с цветом")
            : s >= 28 ? w.extra("score.calm", "спокойный") : w.extra("score.none", "серый")
    }

    /// «спокойный · 34 / 100»; `nil` — оценки нет (нет прогноза): числа не выдумываются.
    public static func scoreLine(_ s: Int?, _ w: WidgetFeed.Words) -> String? {
        s.map { "\(scoreWord($0, w)) · \($0) / 100" }
    }

    // MARK: Съёмки

    /// «16 ч» / «1 ч 20 мин» / «40 мин» — промежуток до двух суток (слова единиц — из словаря виджета).
    public static func span(_ f: WidgetFrame, seconds t: TimeInterval) -> String {
        let minutes = max(1, Int((t / 60).rounded(.up)))
        let h = minutes / 60, m = minutes % 60
        if minutes < 60 { return "\(m) \(f.words[.minShort])" }
        return h < 10 && m > 0 ? "\(h) \(f.words[.hourShort]) \(m) \(f.words[.minShort])" : "\(h) \(f.words[.hourShort])"
    }

    /// «через 16 ч» / «через 3 дня»: до начала съёмки; до двух суток — часами, дальше — словом дней (`inDays`). Идёт или прошла — `nil`.
    public static func untilText(_ f: WidgetFrame, to start: Date, dayOffset: Int) -> String? {
        let t = start.timeIntervalSince(f.now)
        guard t > 0 else { return nil }
        if t < 48 * 3600 { return f.words.extra("in", "через {t}").replacingOccurrences(of: "{t}", with: span(f, seconds: t)) }
        return f.words.inDays(max(2, dayOffset))
    }

    // MARK: Три вида большого (30и.14, выбор Алексея: «большой виджет с рисками-таймером»; эскиз 30и.13 § 9)

    /// Какой из трёх видов рисует большой: `idle` — съёмка не идёт (купол «Света» и блок со съёмками недели или закатами), `photo` — идёт
    /// съёмка без маршрута (окошко Braun, кольцо на всю съёмку), `route` — идёт съёмка с маршрутом (таймлайн точек и риски-таймер по краю).
    public enum State: Equatable, Sendable { case idle, photo, route }

    public static func state(_ f: WidgetFrame) -> State {
        guard f.kind == .live, let shoot = f.primary?.shoot else { return .idle }
        return shoot.stops.isEmpty ? .photo : .route
    }

    /// Какие точки маршрута стоят в таймлайне, если помещается `rows`: окно из `rows` строк с одной прошедшей точкой над текущей (контекст),
    /// сдвинутое так, чтобы не выйти за список. Текущей точки ещё нет (съёмка идёт, а первая точка впереди) — с начала.
    public static func routeWindow(count: Int, current: Int?, rows: Int) -> Range<Int> {
        guard count > 0, rows > 0 else { return 0..<0 }
        let n = min(rows, count)
        let first = max(0, min((current ?? 1) - 1, count - n))
        return first..<(first + n)
    }

    /// Кольцо точек блока отсчёта: доля зажжённых. Съёмка идёт — сколько прошло; впереди — сколько осталось до начала из суток (дальше суток кольцо пусто).
    public static func ringFill(_ s: WidgetFrame.ShootFrame, now: Date) -> Double {
        let start = s.shoot.startDate, end = s.shoot.endDate
        if start <= now { return end > start ? min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start))) : 1 }
        return 1 - min(1, start.timeIntervalSince(now) / 86_400)
    }
}

extension WidgetFeed.Words {
    /// Слово, которого нет в перечислении ключей: из таблицы приложения, иначе запасное (файл старого вида не оставляет плашку без подписи).
    public func extra(_ key: String, _ fallback: String) -> String {
        if let w = table[key], !w.isEmpty { return w }
        return fallback
    }
}
