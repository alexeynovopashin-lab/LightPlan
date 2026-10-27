import Foundation
import LightPlanDomain
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Файл виджета в общей папке приложения и расширения (30б.1, `docs/30b_widget_cut.md` § «Data»).
///
/// Пишет `WidgetFeed` в `group.<адрес приложения>/widget.json` и просит виджет перерисоваться — только если файл
/// изменился. Папку даёт подпись (`Config/LightPlan-iOS.entitlements`); на Mac и в тестах без папки — `nil`.
@MainActor
final class WidgetShare {
    let url: URL
    private var last: Data?

    init(url: URL) {
        self.url = url
    }

    static func live(bundleID: String? = Bundle.main.bundleIdentifier) -> WidgetShare? {
        #if os(iOS)
        guard let id = bundleID,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetFeed.groupID(bundleID: id))
        else { return nil }
        return WidgetShare(url: dir.appendingPathComponent(WidgetFeed.fileName))
        #else
        return nil
        #endif
    }

    /// `true` — файл переписан и виджет позван (замер спайка: перерисовка в ту же секунду).
    @discardableResult
    func publish(_ feed: WidgetFeed) -> Bool {
        let data = feed.encoded()
        guard data != last else { return false }
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        last = data
        #if os(iOS) && canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return true
    }
}

extension AppModel {
    /// Файл виджета: место «Света» и съёмки ближайших семи дней (30б.2) — при запуске (`live()`), при каждой смене места
    /// (`placeChanged`) и при каждой записи данных (`persist()`). Пишется только если файл изменился.
    func publishWidget() {
        guard let share = widgetShare else { return }
        let spot = WidgetFeed.Spot(name: light.locationName, place: place.place)
        let words = PlannerWords(lexicon: lexicon, orgs: snapshot.orgs)
        let zones = place.zones
        let nowDate = now()
        let feed = WidgetFeed.make(
            place: spot, sessions: snapshot.sessions, studios: snapshot.studios, spots: snapshot.spots, now: nowDate,
            manualEnd: settings.manualEnd,
            offset: { point, day in
                if let point { return zones.utcOffsetHours(latitude: point.latitude, longitude: point.longitude, on: day) }
                return place.place.zone.utcOffsetHours(on: day)
            },
            title: { words.typeName($0) },
            names: { words.clientName($0) },
            sign: { PointSign.name(for: $0, place: $1, studio: $2) },
            words: Self.widgetWords(lexicon),
            forecast: widgetForecast(spot, now: nowDate),
            lang: language,
            clock12: ClockText(language: language, preference: Self.clock(settings.clock)).is12)
        share.publish(feed)
    }

    /// Оценки заката ближайших дней места «Света» из настоящего прогноза (30б.2в-5). Прогноза на день нет — оценки нет: числа не выдумываются.
    func widgetForecast(_ spot: WidgetFeed.Spot, now: Date) -> [WidgetFeed.Rating] {
        guard let today = spot.today(at: now) else { return [] }
        return (0..<WidgetFeed.ratingDays).compactMap { off in
            let day = today.adding(days: off)
            guard let w = light.weather.day(for: day), w.real else { return nil }
            return WidgetFeed.Rating(day: WidgetFeed.Rating.key(day), score: w.sunset, quality: w.quality)
        }
    }

    /// Прогноз приходит позже файла (сеть): когда он обновился, файл виджета переписывается (пишется, только если изменился).
    func watchWidgetForecast() {
        withObservationTracking {
            let spot = WidgetFeed.Spot(name: "", place: place.place)
            if let today = spot.today(at: now()) {
                for off in 0..<WidgetFeed.ratingDays { _ = light.weather.day(for: today.adding(days: off)) }
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.publishWidget()
                self.watchWidgetForecast()
            }
        }
    }

    /// Слова виджета на языке приложения: у расширения словаря приложения нет (`WidgetFeed.Words`).
    static func widgetWords(_ lex: Lexicon) -> WidgetFeed.Words {
        let keys: [WidgetFeed.Words.Key: String] = [
            .sunrise: "tele.sunrise", .sunset: "tele.sunset", .golden: "tele.golden", .next: "pane.next",
            .today: "pick.dayToday", .tomorrow: "pick.dayTomorrow", .polarDay: "next.polarDay",
            .polarNight: "next.polarNight", .studio: "studio.sayT", .shoot: "day.actShoot", .route: "card.route",
            .untilPoint: "widget.untilPoint", .untilShoot: "widget.untilShoot", .untilWedding: "widget.untilWedding",
            .wedding: "widget.wedding", .point: "widget.point", .points: "widget.points", .hourShort: "widget.hourShort",
            .minShort: "widget.minShort", .dayLength: "widget.dayLength", .more: "widget.more", .until: "widget.until",
            .rateExcellent: "widget.rateExcellent", .rateGood: "widget.rateGood", .ratePlain: "widget.ratePlain",
            .ratePoor: "widget.ratePoor", .rateFog: "widget.rateFog", .noShootsUntil: "widget.noShootsUntil",
        ]
        var words = WidgetFeed.Words(keys.mapValues { lex.t($0) })
        // «через 3 дня»: падеж зависит от числа, у расширения склонений нет — фразы на каждое число готовит приложение.
        for n in 2..<WidgetFrame.weekDays { words.table["inDays.\(n)"] = lex.t("when.inDays", ["n": lex.count("unit.day", n)]) }
        return words
    }

    /// `lightplan://day/ГГГГ-ММ-ДД`: нажатие на виджет свободного дня открывает этот день в «Съёмках».
    @discardableResult
    func openDayLink(_ url: URL) -> Bool {
        guard let day = WidgetFeed.day(in: url) else { return false }
        closeCard()
        tab = .planner
        planner.enterDay(day)
        return true
    }
}
