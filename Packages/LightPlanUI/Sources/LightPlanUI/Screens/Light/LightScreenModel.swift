import Foundation
import Observation
import LightPlanCore
import LightPlanData

/// Хозяин экрана «Свет»: держит `TimebarState` (тот же таймбар, что уже есть
/// на экране, — купол и лента остаются его же данными) и `WeatherStore`,
/// считает `LightTelemetry` заново на каждую минуту.
///
/// **Просто/Астро — временное поле, а не система настроек.** Полноценного
/// экрана настроек ещё нет (итерация 19а). Решение исполнителя: тот же приём,
/// каким итерация 17 завела `showMoon` в `TimebarState`, — простое
/// `@Observable`-поле здесь, а не в `TimebarState`: тумблер режима принадлежит
/// одному экрану «Свет», а `showMoon` делят купол и барабан таймбара сразу
/// двух разных модулей композиции. Когда экран настроек появится, оба поля
/// переедут в общее хранилище разом — до тех пор это два отдельных временных
/// поля, а не одно на будущее хранилище.
@MainActor
@Observable
public final class LightScreenModel {

    public let timebar: TimebarState
    public let weather: WeatherStore

    /// Просто/Астро: `false` — «Просто» (спойлер «Подробно» скрыт целиком),
    /// `true` — «Астро». Веб хранит это в настройках приложения; здесь —
    /// временно, см. комментарий типа выше.
    public var proMode = false

    /// Солнце или луна на куполе и в первой группе спойлера — тот же
    /// тумблер, что уже делят `DomeView` и барабан таймбара.
    public var moonMode: Bool {
        get { timebar.showMoon }
        set { timebar.showMoon = newValue }
    }

    private let language: String
    private let lexicon: Lexicon
    private let clock: ClockText
    private let dateText: DateText

    public init(timebar: TimebarState, weather: WeatherStore, language: String = "ru") {
        self.timebar = timebar
        self.weather = weather
        self.language = language
        self.lexicon = Lexicon(language)
        self.clock = ClockText(language: language)
        self.dateText = DateText(language: language, timeZone: TimeZone(identifier: timebar.place.zone.identifier) ?? .current)
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
            lexicon: lexicon, clock: clock
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

    /// Демо-место (Барнаул, см. `RootView`) — геокодера ещё нет (итерация 12),
    /// поэтому имя места здесь буквальное, а не из справочника.
    private var headerLocationName: String { "Барнаул" }

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

    private var timeZone: TimeZone { TimeZone(identifier: timebar.place.zone.identifier) ?? .current }
}
