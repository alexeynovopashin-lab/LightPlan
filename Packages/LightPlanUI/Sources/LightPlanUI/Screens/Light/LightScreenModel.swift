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
