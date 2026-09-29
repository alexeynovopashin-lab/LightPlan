import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 27, шаг 2: тело маршрута в карточке — знак точки по слову, состояние
/// точки, конец дня в строке, «Дальше» на границах. Таблица слов — из
/// `card_reference.md` («Маршрут и референсы — итерация 27», § 2), сверена с
/// бетой скриптом `tools/pointwords_check.js`.
@MainActor
struct CardRouteBodyTests {

    private struct Quiet: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            HourlyWeather(time: [], cloud: [], temperature: [], windSpeed: [], precipitation: [], weatherCode: [])
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func model(_ s: Session, at iso: String) -> AppModel {
        var snap = Snapshot()
        snap.sessions = [s]
        snap.practice = "ru"
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: Quiet(), now: { now })
    }

    private static func day(_ route: [RoutePoint], date: Int = 21) -> Session {
        var s = Session(id: "w", kind: .shoot, day: CivilDate(year: 2026, month: 9, day: date),
                        start: 480, end: 1290, duration: 810, genre: .portrait)
        s.route = route
        return s
    }

    /// Свадебный день из 12 точек (замер беты: 18:00 — восьмая «Банкет» текущая).
    private static let wedding: [(String, Int, String)] = [
        ("Сборы невесты", 480, "rings"), ("Сборы жениха", 520, "rings"), ("Первый взгляд", 600, "couple"),
        ("ЗАГС", 660, "hall"), ("Прогулка", 720, "park"), ("Венчание", 780, "church"),
        ("Фуршет", 900, "toast"), ("Банкет", 1000, "feast"), ("Первый танец", 1100, "dance"),
        ("Торт", 1150, "cake"), ("Закат", 1180, "sunset"), ("Салют", 1230, "fireworks"),
    ]

    // MARK: - Знак по слову

    /// 40 названий из справки: знак, ярус и порядок правил — как в бете.
    @Test func fortyWordsPickTheWebSign() {
        let table: [(String, String)] = [
        ("Сборы невесты", "rings"),
        ("Мехенди", "mehendi"),
        ("ЗАГС", "hall"),
        ("Венчание", "church"),
        ("Выездная церемония", "arch"),
        ("Первый взгляд", "couple"),
        ("Рассвет у реки", "sunrise"),
        ("Закат на мосту", "sunset"),
        ("Золотой час", "golden"),
        ("Золотой мост", "bridge"),
        ("Светлана", "dot"),
        ("Свет в окне", "sun"),
        ("Банкет", "feast"),
        ("Бар-мицва", "dot"),
        ("Подарки гостям", "gift"),
        ("Усадьба", "manor"),
        ("Сад усадьбы", "manor"),
        ("Кот", "cat"),
        ("Катерина", "dot"),
        ("Прогулка", "park"),
        ("Прогулка у водопада", "waterfall"),
        ("Съёмка на крыше", "rooftop"),
        ("Фотосессия", "camera"),
        ("Пара", "couple"),
        ("Автобус гостей", "bus"),
        ("Уборка площадки", "broom"),
        ("Тост", "toast"),
        ("Торт со свечами", "cake_bd"),
        ("Первый танец", "dance"),
        ("Смотровая площадка", "viewpoint"),
        ("Дворцовая площадь", "plaza"),
        ("Djemaa el-Fna", "plaza"),
        ("Парковка", "cars"),
        ("Сад", "park"),
        ("Портреты", "camera"),
        ("Шикарный вид", "dot"),
        ("Boat trip", "boat"),
        ("Волейбол на пляже", "volleyball"),
        ("Никях", "mosque"),
        ("Тадж-Махал", "mausoleum"),
        ]
        #expect(table.count == 40)
        for (title, sign) in table {
            #expect(PointSign.name(for: title) == sign, "\(title)")
        }
    }

    /// Название + место + студия: сильное имя бьёт место, слабое уступает.
    @Test func placeAndStudioDecideOnlyForWeakNames() {
        #expect(PointSign.name(for: "Фотосессия", place: "Gardens by the Bay") == "glasshouse")
        #expect(PointSign.name(for: "Церемония", place: "пляж") == "arch")
        #expect(PointSign.name(for: "Прогулка", place: "гора") == "mountain")
        #expect(PointSign.name(for: "Съёмка", place: "Уюни") == "salt_flat")
        #expect(PointSign.name(for: "Портреты", place: "Тадж-Махал") == "mausoleum")
        #expect(PointSign.name(for: "Прогулка", place: "Кинтамани") == "park")
        #expect(PointSign.name(for: "Фотосессия", studio: true) == "studio")
    }

    // MARK: - Лента из 12 точек

    /// День из 12 точек даёт ленту из 12 строк с теми же знаками, что в вебе,
    /// и состояниями на 18:00: семь прошедших, текущая «Банкет», четыре впереди.
    @Test func weddingDayGivesTwelveLines() {
        let s = Self.day(Self.wedding.map { RoutePoint(start: $0.1, name: $0.0) })
        let app = model(s, at: "2026-09-21T18:00:00+03:00")
        let lines = app.cardRouteLines(app.sessions[0])
        #expect(lines.count == 12)
        #expect(lines.map(\.sign) == Self.wedding.map(\.2))
        #expect(lines.map(\.name) == Self.wedding.map(\.0))
        #expect(lines.map(\.state) == Array(repeating: .past, count: 7) + [.now] + Array(repeating: .ahead, count: 4))
        #expect(lines[0].time == "08:00" && lines[7].time == "16:40")
        #expect(lines.allSatisfy { $0.place == nil })
    }

    /// Место точки: строка под именем; знак берёт его, когда имя молчит.
    @Test func placeUnderNameAndInSign() {
        let s = Self.day([RoutePoint(start: 600, name: "Фотосессия", placeText: "Gardens by the Bay")])
        let app = model(s, at: "2026-09-21T09:00:00+03:00")
        let l = app.cardRouteLines(app.sessions[0])[0]
        #expect(l.place == "Gardens by the Bay" && l.sign == "glasshouse")
    }

    // MARK: - Слово света

    /// Слово света только у «отлично» (замер числами: Москва, 21.09): золотой час
    /// в 18:20, синий (синим цветом) в 19:10; день, вечер без света и ночь молчат.
    @Test func lightWordOnlyWhereLightIsExcellent() {
        var s = Self.day(Self.wedding.map { RoutePoint(start: $0.1, name: $0.0) })
        s.latitude = 55.75; s.longitude = 37.62
        let app = model(s, at: "2026-09-21T18:00:00+03:00")
        let l = app.cardRouteLines(app.sessions[0])
        #expect(l.map { $0.word } == [nil, nil, nil, nil, nil, nil, nil, nil, "Золотой час", "Синий час", nil, nil])
        #expect(l.map(\.blue) == (0..<12).map { $0 == 9 })
    }

    // MARK: - Состояние точки

    @Test func stateBoundaries() {
        let r = [10, 20, 20, 30].map { RoutePoint(start: $0, name: "т") }
        // Ровно на начале: текущая — последняя из равных, ровные ей не «прошедшие».
        #expect(AppModel.routeStates(r, now: 20) == [.past, .ahead, .now, .ahead])
        #expect(AppModel.routeStates(r, now: 21) == [.past, .past, .now, .ahead])
        #expect(AppModel.routeStates(r, now: 31) == [.past, .past, .past, .now])
        // До первой точки и вне суток съёмки — никто не отмечен.
        #expect(AppModel.routeStates(r, now: 5) == Array(repeating: .ahead, count: 4))
        #expect(AppModel.routeStates(r, now: nil) == Array(repeating: .ahead, count: 4))
    }

    /// Вне суток съёмки лента без отметок.
    @Test func linesOutsideShootDayAreUnmarked() {
        let s = Self.day(Self.wedding.map { RoutePoint(start: $0.1, name: $0.0) })
        let app = model(s, at: "2026-09-20T18:00:00+03:00")
        #expect(app.cardRouteLines(app.sessions[0]).allSatisfy { $0.state == .ahead })
    }

    // MARK: - Конец дня в строке

    /// Ошибка веба 23: конец — самый поздний из концов, а не конец последней
    /// по началу точки.
    @Test func foldEndIsLatestEnd() {
        let s = Self.day([RoutePoint(start: 600, end: 1200, name: "Долгая"), RoutePoint(start: 700, end: 720, name: "Короткая")])
        let app = model(s, at: "2026-09-21T09:00:00+03:00")
        let sub = app.cardRouteFold(app.sessions[0])!.sub.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(sub == "2 точки · 10:00 – 20:00")
    }

    // MARK: - «Дальше» на границах

    private func nextTitle(_ s: Session, at iso: String, phase: EventPhase = .during) -> String? {
        let app = model(s, at: iso)
        return app.cardPanes(app.sessions[0], phase: phase).first { $0.kind == .next }?.title
    }

    @Test func nextTileBoundaries() {
        let s = Self.day([RoutePoint(start: 600, name: "Сбор"), RoutePoint(start: 780, name: "Парк"), RoutePoint(start: 900, name: "Студия")])
        // Ровно на начале «Парка» он уже идёт — дальше «Студия».
        #expect(nextTitle(s, at: "2026-09-21T13:00:00+03:00") == "Студия")
        #expect(nextTitle(s, at: "2026-09-21T12:59:00+03:00") == "Парк")
        // До первой — первая; после последней — плитки нет.
        #expect(nextTitle(s, at: "2026-09-21T09:00:00+03:00") == "Сбор")
        #expect(nextTitle(s, at: "2026-09-21T15:00:00+03:00") == nil)
        // После события — нет, и в другой день — нет.
        #expect(nextTitle(s, at: "2026-09-21T09:00:00+03:00", phase: .after) == nil)
        #expect(nextTitle(s, at: "2026-09-22T09:00:00+03:00", phase: .after) == nil)
    }
}
