import Foundation
import Observation
import LightPlanCore
import LightPlanData

/// Хозяин экрана «Свет»: держит `TimebarState` (тот же таймбар, что уже есть
/// на экране, — купол и лента остаются его же данными) и `WeatherStore`,
/// считает `LightTelemetry` заново на каждую минуту.
///
/// **Просто/Астро, часы и градусы приходят из настроек** (итерация 19а):
/// хранит их `AppModel`, сюда они доезжают присвоением без пересоздания
/// экрана — выбранная минута и день на таймбаре остаются, где были.
/// `showMoon` остался в `TimebarState`: его делят купол и барабан, и в
/// настройках веба его нет.
@MainActor
@Observable
public final class LightScreenModel {

    public let timebar: TimebarState
    public let weather: WeatherStore

    /// Просто/Астро: `false` — «Просто» (спойлер «Подробно» скрыт целиком),
    /// `true` — «Астро».
    public var proMode = false

    /// Градусы Фаренгейта вместо Цельсия (`tempUnit` веба).
    public var fahrenheit = false

    /// Имя места в шапке. До итерации 20 (карта, выбор места руками) это
    /// город по умолчанию: из настроек, из геолокации или столица.
    public var locationName: String
    /// Строка под именем — область или страна (`hLocSub` веба), от геокодера.
    public var locationSub = ""

    public var clockPreference: ClockPreference = .auto {
        didSet {
            clock = ClockText(language: language, preference: clockPreference)
            timebar.setClockPreference(clockPreference)
        }
    }

    /// Солнце или луна на куполе и в первой группе спойлера — тот же
    /// тумблер, что уже делят `DomeView` и барабан таймбара.
    public var moonMode: Bool {
        get { timebar.showMoon }
        set { timebar.showMoon = newValue }
    }

    /// Лист «Когда смотрим» открыт — тап по показаниям купола (19в).
    public var pickerOpen = false

    // MARK: - Светило пальцем (итерация 19в)

    /// Минута под пальцем в рамке купола размера `size`; `nil` — ниже
    /// горизонта. Дуга — того светила, что на куполе.
    func domeMinute(at p: CGPoint, in size: CGSize) -> Minutes? {
        guard let f = DomeDrag.fraction(at: DomeDrag.viewPoint(p, in: size)) else { return nil }
        let m = timebar.machine
        let arc = DomeDrag.arc(moon: moonMode, sun: timebar.solarDay, date: m.selectedDate, place: timebar.place,
                               at: m.viewMinute, mint: m.mint, maxt: m.maxt)
        return DomeDrag.minute(fraction: f, arcStart: arc.start, arcEnd: arc.end, mint: m.mint, maxt: m.maxt)
    }

    func dragDome(at p: CGPoint, in size: CGSize) {
        if let t = domeMinute(at: p, in: size) { timebar.dragDome(to: t) }
    }

    /// Выбор из листа: `onDone` веба — день и время суток по часам места.
    public func pick(day: CivilDate, minute: Minutes) {
        timebar.show(day: day, minute: minute)
    }

    // MARK: - Лист «Когда смотрим»

    /// Дни барабана даты: месяц назад и год вперёд от сегодняшнего дня места
    /// (`BACK = 30`, `AHEAD = 365` веба), «Сегодня», «Завтра», дальше «ПТ 2
    /// октября».
    static let pickBack = 30, pickAhead = 365

    func pickerDays() -> [(day: CivilDate, label: String)] {
        let today = timebar.todayInPlace, dt = dateText
        return (-Self.pickBack...Self.pickAhead).map { o in
            let d = today.adding(days: o)
            let label = o == 0 ? lexicon.t("pick.dayToday") : o == 1 ? lexicon.t("pick.dayTomorrow")
                : dt.wdShort(asFoundationDate(d)) + " " + dt.dMon(asFoundationDate(d))
            return (d, label)
        }
    }

    /// Час на барабане — по выбранным часам: «07» или «7 AM» (`hourLabel`
    /// веба); значение всегда 0–23.
    func pickerHourLabel(_ h: Int) -> String {
        clock.is12 ? clock.fmt(Double(h * 60)).replacingOccurrences(of: #"^(\d+):00"#, with: "$1", options: .regularExpression)
            : String(format: "%02d", h)
    }

    /// С чего лист открывается: день и время, которые на экране. Веб берёт
    /// выбранный день ленты и минуту по модулю суток — за полночью у него
    /// лист открывается на день раньше, чем в шапке (DECISIONS, 19в).
    var pickerStart: (day: CivilDate, minute: Int) {
        let t = timebar.machine.viewMinute.rounded()
        let wrapped = Int(((t.truncatingRemainder(dividingBy: 1440)) + 1440).truncatingRemainder(dividingBy: 1440))
        return (viewDate(t: t), wrapped)
    }

    private let language: String
    private let lexicon: Lexicon
    private var clock: ClockText

    public init(timebar: TimebarState, weather: WeatherStore, language: String = "ru",
                locationName: String = "", clockPreference: ClockPreference = .auto) {
        self.timebar = timebar
        self.weather = weather
        self.language = language
        self.locationName = locationName
        self.clockPreference = clockPreference
        self.lexicon = Lexicon(language)
        self.clock = ClockText(language: language, preference: clockPreference)
    }

    /// Данные экрана на текущую минуту таймбара — порт `renderToday`.
    public var telemetry: LightTelemetry {
        let t = timebar.machine.viewMinute
        let sun = timebar.solarDay
        let date = timebar.machine.selectedDate
        let weatherDay = weather.day(for: date)
        let air = sun.set.map { setMinutes in
            weather.airSample(for: date, hour: Int(min(23, max(0, (setMinutes / 60).rounded()))))
        } ?? weather.airSample(for: date, hour: 19)

        return LightTelemetry.build(
            sun: sun, t: t, moon: moonMode, moonSnapshot: moonMode ? moonSnapshot(date: date, t: t, sun: sun) : nil,
            weather: weatherDay, weatherLive: weather.isLive, air: air,
            headerLocationName: headerLocationName, headerDateLabel: headerDateLabel(t: t),
            headerNote: headerNote(t: t),
            lexicon: lexicon, clock: clock, fahrenheit: fahrenheit
        )
    }

    /// Слово по ключу словаря — вид зовёт это для подписей, которые
    /// `LightTelemetry` не переводит сам (заголовки строк телеметрии,
    /// кнопка съёмки: их текст не входит в модель, потому что не зависит от
    /// минуты, только от языка).
    public func lexiconWord(_ key: String) -> String { lexicon.t(key) }

    // MARK: - Луна для спойлера

    private func moonSnapshot(date: CivilDate, t: Minutes, sun: SolarDay) -> MoonSnapshot {
        let sample = MoonSample(date: date, minutes: t, place: timebar.place)
        let arc = MoonDay(date: date, place: timebar.place).arc(at: t)
        let riseAz = arc.map { MoonSample(date: date, minutes: $0.rise, place: timebar.place).azimuth }
        let setAz = arc.map { MoonSample(date: date, minutes: $0.set, place: timebar.place).azimuth }
        return MoonSnapshot(phase: sample.phase, azimuth: sample.azimuth, altitude: sample.altitude,
                             distance: sample.distance, arc: arc, riseAzimuth: riseAz, setAzimuth: setAz)
    }

    // MARK: - Шапка: место, дата, «сегодня/через…/…назад»

    private var headerLocationName: String { locationName }

    private func viewDate(t: Minutes) -> CivilDate {
        timebar.machine.selectedDate.adding(days: Int((t / 1440).rounded(.down)))
    }

    private func headerDateLabel(t: Minutes) -> String {
        let d = asFoundationDate(viewDate(t: t))
        return dateText.wdShort(d) + " · " + dateText.dMon(d)
    }

    private func headerNote(t: Minutes) -> String {
        let shown = viewDate(t: t)
        let today = timebar.todayInPlace
        if shown == today { return lexicon.t("today.now") }
        // `CivilDate` не сравнивается напрямую (не `Comparable`) — оба дня
        // несут местную полночь, и порядок дат совпадает с порядком времён
        // (веб `d > n` на объектах `Date`).
        let shownAtMidnight = asFoundationDate(shown), todayAtMidnight = asFoundationDate(today)
        return shownAtMidnight > todayAtMidnight ? lexicon.t("today.ahead") : lexicon.t("today.past")
    }

    private func asFoundationDate(_ cd: CivilDate) -> Date {
        DateText.carrier(year: cd.year, month: cd.month - 1, day: cd.day, in: timeZone)
    }

    /// Пояс берётся у места на каждый вызов: город по умолчанию уточняет
    /// зону ответом геокодера уже после того, как экран построен.
    private var dateText: DateText { DateText(language: language, timeZone: timeZone) }

    private var timeZone: TimeZone { TimeZone(identifier: timebar.place.zone.identifier) ?? .current }
}
