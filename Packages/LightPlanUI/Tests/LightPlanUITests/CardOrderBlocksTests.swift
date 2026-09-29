import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 26, шаг 4: блоки заказа (сделка, задание, модели, документы,
/// заметки, сдача, гонорар), «Место и дальше», свёрнутая строка маршрута;
/// вынос бумаг и денег вперёд в режиме перестановки у заказа «после»; тревога
/// «прогноз переменился» (`#cdShift`) и её память `wxSeen`/`wxTold`/`notif`.
@MainActor
struct CardOrderBlocksTests {

    private struct SkySource: WeatherSource {
        let rain: Bool
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            var time: [String] = []
            let d0 = CivilDate(year: 2026, month: 9, day: 15)
            for k in 0..<21 {
                let d = d0.adding(days: k)
                for h in 0..<24 { time.append(String(format: "%04d-%02d-%02dT%02d:00", d.year, d.month, d.day, h)) }
            }
            let n = time.count
            return HourlyWeather(time: time, cloud: Array(repeating: rain ? 95 : 5, count: n),
                                 temperature: Array(repeating: 12, count: n), windSpeed: Array(repeating: 2, count: n),
                                 precipitation: Array(repeating: rain ? 3 : 0, count: n),
                                 weatherCode: Array(repeating: rain ? 61 : 0, count: n))
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

    private func model(_ snap: Snapshot, rain: Bool = false, store: Store? = nil,
                       at iso: String = "2026-09-20T12:00:00+03:00") -> AppModel {
        let now = ISO8601DateFormatter().date(from: iso)!
        return AppModel(snapshot: snap, store: store, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: SkySource(rain: rain), now: { now })
    }

    private func rec(_ app: AppModel, _ id: String) -> Session { app.sessions.first { $0.id == id }! }

    private func digits(_ s: String) -> String { s.filter(\.isNumber) }

    /// Заказ: предметка 24.09 10:00–12:00, задание, договор, гонорар, сдача.
    private static func order(day: Int = 24) -> Session {
        var c = Session(id: "c", kind: .shoot, day: CivilDate(year: 2026, month: 9, day: day),
                        start: 600, end: 720, duration: 120, genre: .product)
        c.brief = "каталог"; c.notes = "зонт"
        c.docs = [Attachment(source: .link, path: nil, name: "Договор", size: nil,
                             url: "https://disk.example.com/i/dogovor.pdf", kind: .contract),
                  Attachment(source: .doc, path: "p", name: "смета.xlsx", size: 20480, url: nil, kind: nil)]
        c.pay = .flat; c.rate = 40000; c.expense = 5000; c.prepay = 10000
        return c
    }

    private static func portrait(_ id: String = "p", day: Int = 27) -> Session {
        Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: 9, day: day),
                start: 600, end: 720, duration: 120, genre: .portrait)
    }

    private static func snap(_ list: [Session], practice: String = "ru") -> Snapshot {
        var s = Snapshot()
        s.sessions = list
        s.practice = practice
        return s
    }

    // MARK: - Порядок «после» у заказа

    /// Режим перестановки показывает блоки так же, как карточка: у заказа
    /// после съёмки сделка, документы, гонорар и сдача впереди (решение
    /// Алексея 29.09 — как в бете).
    @Test func rowsLiftPapersAndMoneyForClientAfterShoot() {
        let app = model(Self.snap([Self.order(), Self.portrait()]), at: "2026-09-25T12:00:00+03:00")
        let c = rec(app, "c")
        #expect(app.phase(of: c) == .after)
        #expect(app.cardOrderRows(c, phase: .after) == [.deal, .docs, .money, .delivery, .day, .brief, .notes])
        #expect(app.cardOrderRows(c, phase: .after) == app.cardBlocks(c, phase: .after))
        // Портрет и заказ до съёмки — без выноса.
        let p = rec(app, "p")
        #expect(app.cardOrderRows(p, phase: .after) == [.day, .delivery])
        #expect(app.cardOrderRows(c, phase: .before) == [.deal, .day, .brief, .docs, .notes, .delivery, .money])
    }

    /// Перетащили заметки наверх списка «после»: в порядок группы уходит
    /// только этот блок, остальные стоят где стояли; на карточке вынос вперёд
    /// всё равно держится (как в бете).
    @Test func dragInAfterListMovesOnlyThatBlock() {
        let app = model(Self.snap([Self.order()]), at: "2026-09-25T12:00:00+03:00")
        let c = rec(app, "c")
        app.moveCardBlock(.notes, to: 0, for: c)
        #expect(app.cardOrderRows(c, phase: .before) == [.notes, .deal, .day, .brief, .docs, .delivery, .money])
        #expect(app.cardOrderRows(c, phase: .after) == [.deal, .docs, .money, .delivery, .notes, .day, .brief])
        #expect(app.cardBlocks(c, phase: .after) == app.cardOrderRows(c, phase: .after))
    }

    /// Выключенный блок остаётся строкой списка «после», а на карточке его нет.
    @Test func offBlockStaysInAfterRows() {
        let app = model(Self.snap([Self.order()]), at: "2026-09-25T12:00:00+03:00")
        let c = rec(app, "c")
        app.setCardBlock(.money, shown: false, for: c)
        #expect(app.cardOrderRows(c, phase: .after).contains(.money))
        #expect(!app.cardBlocks(c, phase: .after).contains(.money))
    }

    // MARK: - Появление блоков заказа

    @Test func eachOrderBlockAppearsByItsOwnCondition() {
        var bare = Self.order(day: 25); bare.id = "b"
        bare.brief = ""; bare.models = ""; bare.docs = []; bare.notes = ""; bare.expense = 0; bare.pay = nil
        var withModels = bare; withModels.id = "m"; withModels.day = CivilDate(year: 2026, month: 9, day: 26); withModels.models = "Аня\n\n Оля "
        let app = model(Self.snap([Self.order(), bare, withModels]))
        func shown(_ id: String) -> [CardBlock] { let s = rec(app, id); return app.cardBlocks(s, phase: app.phase(of: s)) }
        #expect(shown("c") == [.deal, .day, .brief, .docs, .notes, .delivery, .money])
        #expect(shown("b") == [.deal, .day, .delivery])
        #expect(shown("m") == [.deal, .day, .models, .delivery])
    }

    /// Сдача — только у жанра со сдачей: у пейзажа и стрита её нет.
    @Test func deliveryOnlyForGenreWithHandover() {
        var street = Self.portrait("s"); street.genre = .street
        let app = model(Self.snap([Self.portrait(), street]))
        #expect(app.cardBlocks(rec(app, "p"), phase: .before).contains(.delivery))
        #expect(!app.cardBlocks(rec(app, "s"), phase: .before).contains(.delivery))
    }

    // MARK: - Сделка

    @Test func dealChainByPractice() {
        var noPrepay = Self.order(); noPrepay.prepay = 0
        let app = model(Self.snap([noPrepay, Self.portrait()]))
        let d = app.cardDeal(rec(app, "c"))!
        #expect(d.links.map(\.step) == [.brief, .contract, .invoice, .pay, .act])
        #expect(d.links.map(\.done) == [true, true, false, false, false])
        #expect(d.links.map(\.isNext) == [false, false, true, false, false])
        #expect(d.caption == "осталось 3 шага")
        // У частного клиента при практике ru блока нет; при us — есть.
        #expect(app.cardDeal(rec(app, "p")) == nil)
        let us = model(Self.snap([Self.portrait()], practice: "us"))
        #expect(us.cardBlocks(rec(us, "p"), phase: .before).contains(.deal))
        #expect(us.cardDeal(rec(us, "p"))?.links.map(\.step) == [.brief, .contract, .retainer, .balance, .release])
    }

    @Test func dealCaptionWaitOneAndAllDoneAndPrepaid() {
        var one = Self.order(); one.id = "o"
        one.docs.append(Attachment(source: .link, name: "Счёт", url: "https://x.example.com/a", kind: .invoice))
        one.docs.append(Attachment(source: .link, name: "Акт", url: "https://x.example.com/b", kind: .act))
        one.prepay = 40000
        var half = Self.order(); half.id = "h"
        half.docs.append(Attachment(source: .link, name: "Счёт", url: "https://x.example.com/a", kind: .invoice))
        half.docs.append(Attachment(source: .link, name: "Акт", url: "https://x.example.com/b", kind: .act))
        let app = model(Self.snap([one, half]))
        #expect(app.cardDeal(rec(app, "o"))?.caption == "всё закрыто")
        // Оплата внесена частью — подпись про остаток, а не «ждём».
        #expect(app.cardDeal(rec(app, "h"))?.caption == "внесена предоплата · ждём остаток")
    }

    // MARK: - Гонорар, сдача

    @Test func moneyBlockNumbers() {
        let app = model(Self.snap([Self.order()]))
        let m = app.cardMoney(rec(app, "c"))!
        #expect(digits(m.income) == "40000")
        #expect(digits(m.expenseNote ?? "") == "5000")
        #expect(digits(m.prepayNote ?? "") == "1000030000")
        #expect(digits(m.net) == "35000")
        var plain = Self.order(); plain.id = "q"; plain.expense = 0; plain.prepay = 0
        let app2 = model(Self.snap([plain]))
        let m2 = app2.cardMoney(rec(app2, "q"))!
        #expect(m2.expenseNote == nil && m2.prepayNote == nil)
    }

    @Test func deliveryWordsAndToggle() {
        var sent = Self.order(day: 20); sent.id = "s"
        sent.delivered = true
        sent.deliveredAt = ISO8601DateFormatter().date(from: "2026-09-28T12:00:00+03:00")
        let app = model(Self.snap([Self.order(), sent]), at: "2026-09-25T12:00:00+03:00")
        let due = app.cardDelivery(rec(app, "c"))!
        #expect(due.label.hasPrefix("сдать за"))
        let dd = Delivery.deadline(for: rec(app, "c"), setting: app.snapshotForTests.delivery,
                                   prefs: app.snapshotForTests.genrePrefs)!
        #expect(digits(due.byDate ?? "") == String(dd.day))
        #expect(!due.delivered)
        let done = app.cardDelivery(rec(app, "s"))!
        #expect(done.label.hasPrefix("сдан за 8"))
        #expect(done.byDate == nil && done.delivered)
        // Тап по строке: сдан с датой «сейчас», второй тап снимает.
        app.toggleDelivered(id: "c")
        #expect(rec(app, "c").delivered && rec(app, "c").deliveredAt != nil)
        app.toggleDelivered(id: "c")
        #expect(!rec(app, "c").delivered && rec(app, "c").deliveredAt == nil)
    }

    // MARK: - Задание, модели, документы, заметки, маршрут

    @Test func textBlocksAndDocsRows() {
        var c = Self.order(); c.models = "Аня\n\n Оля "
        c.route = [RoutePoint(start: 660, end: 720, name: "Парк"), RoutePoint(start: 780, name: "Студия")]
        let app = model(Self.snap([c]))
        let s = rec(app, "c")
        #expect(app.cardModels(s) == ["Аня", "Оля"])
        #expect(app.cardModelsTitle(s) == "Модели · 2")
        let docs = app.cardDocRows(s)
        #expect(docs.map(\.name) == ["dogovor.pdf", "смета.xlsx"])
        #expect(docs.map(\.kind) == ["disk.example.com", "XLSX · 20 КБ"])
        #expect(app.cardDocsCount(s) == "2 документа")
        let r = app.cardRouteFold(s)!
        #expect(r.sub.split(whereSeparator: \.isWhitespace).joined(separator: " ") == "2 точки · 11:00 – 13:00")
    }

    // MARK: - Место и дальше

    @Test func panesFromRecordFields() {
        var s = Self.portrait()
        s.guests = 30; s.breed = "корги"; s.trip = true; s.tripPlace = "Сочи"; s.gear = ["a", "b"]
        let app = model(Self.snap([s]))
        let panes = app.cardPanes(rec(app, "p"), phase: .before)
        #expect(panes.map(\.kind) == [.guests, .breed, .trip, .gear])
        #expect(panes.map(\.wide) == [false, false, false, false])
        #expect(panes[0].value == "30" && panes[1].title == "корги" && panes[2].title == "Сочи" && panes[3].value == "2")
        #expect(app.cardBlocks(rec(app, "p"), phase: .before).contains(.place))
    }

    /// Нечётное число половинок — последняя растягивается на ряд.
    @Test func oddHalfTileStretches() {
        var s = Self.portrait(); s.guests = 5; s.breed = "лабрадор"; s.trip = true
        let app = model(Self.snap([s]))
        let panes = app.cardPanes(rec(app, "p"), phase: .before)
        #expect(panes.map(\.wide) == [false, false, true])
        #expect(panes.last?.title == "в другой город")
    }

    @Test func noFieldsNoPlaceBlock() {
        let app = model(Self.snap([Self.portrait()]))
        #expect(app.cardPanes(rec(app, "p"), phase: .before).isEmpty)
        #expect(!app.cardBlocks(rec(app, "p"), phase: .before).contains(.place))
    }

    /// Плитка места: имя до первой запятой, город под ним, погода точки.
    @Test func placeTileWithWeather() async {
        var s = Self.portrait(day: 21)
        s.place = "Парк Горького, Москва"; s.placeTown = "Москва"; s.latitude = 55.75; s.longitude = 37.62
        let app = model(Self.snap([s]), rain: true)
        app.openCard(id: "p")
        await app.pointWeather.settled()
        let tile = app.cardPanes(rec(app, "p"), phase: .before).first { $0.kind == .place }!
        #expect(tile.wide && tile.title == "Парк Горького")
        #expect(tile.sub == "Москва")
        #expect(tile.weather?.sky == "rain" && tile.weather?.temp == "12°" && tile.weather?.word == "Дождь")
        // После съёмки плитки места нет.
        #expect(app.cardPanes(rec(app, "p"), phase: .after).first { $0.kind == .place } == nil)
    }

    /// «Дальше»: следующая точка сегодня, через сколько и во сколько.
    @Test func nextTileToday() {
        var s = Self.portrait(day: 21)
        s.route = [RoutePoint(start: 600, name: "Сбор"), RoutePoint(start: 780, name: "Парк"), RoutePoint(start: 900, name: "Студия")]
        let app = model(Self.snap([s]), at: "2026-09-21T11:00:00+03:00")
        let next = app.cardPanes(rec(app, "p"), phase: .during).first { $0.kind == .next }!
        #expect(next.title == "Парк" && next.sub?.contains("2 ч") == true && next.sub?.contains("13:00") == true)
        // Не в день съёмки — «Дальше» нет.
        let other = model(Self.snap([s]), at: "2026-09-20T11:00:00+03:00")
        #expect(other.cardPanes(rec(other, "p"), phase: .before).first { $0.kind == .next } == nil)
    }

    // MARK: - Тревога «прогноз переменился»

    private static func shootAt(_ id: String = "a", day: Int = 21) -> Session {
        var s = Session(id: id, kind: .shoot, day: CivilDate(year: 2026, month: 9, day: day),
                        start: 1080, end: 1200, duration: 120, genre: .portrait)
        s.latitude = 55.75; s.longitude = 37.62
        return s
    }

    private func seen(_ q: String, _ sc: Int?, id: String = "a") -> JSONValue {
        .object([id: .object(["q": .string(q), "sc": sc.map { .number(Double($0)) } ?? .null])])
    }

    private func shiftApp(seen: JSONValue?, rain: Bool, notif: JSONValue? = nil, day: Int = 21,
                          at iso: String = "2026-09-20T12:00:00+03:00") async -> (AppModel, Session) {
        var snap = Self.snap([Self.shootAt(day: day)])
        if let seen { snap.extra["wxSeen"] = seen }
        if let notif { snap.extra["notif"] = notif }
        let app = model(snap, rain: rain, at: iso)
        app.openCard(id: "a")
        await app.pointWeather.settled()
        return (app, rec(app, "a"))
    }

    @Test func shiftAlertWorseAndBetter() async {
        // Обещали ясно, пришёл дождь — «испортился».
        let (rain, s1) = await shiftApp(seen: seen("excellent", 90), rain: true)
        let worse = rain.cardShift(s1, phase: .before)
        #expect(worse?.title == "Прогноз испортился")
        #expect(worse?.text.contains("Балл заката был 90 из 100") == true)
        // Обещали дождь без балла, пришло ясное небо — «лучше», слова про небо.
        let (clear, s2) = await shiftApp(seen: seen("poor", nil), rain: false)
        let better = clear.cardShift(s2, phase: .before)
        #expect(better?.title == "Прогноз стал лучше")
        #expect(better?.text.hasPrefix("Небо обещали — дождь, теперь") == true)
    }

    @Test func shiftAlertSilentWithoutMemoryOrSameForecast() async {
        let (fresh, s) = await shiftApp(seen: nil, rain: false)
        #expect(fresh.cardShift(s, phase: .before) == nil)          // первое знакомство — не смена
        let now = fresh.cardSkySnap(s)!
        let (same, s2) = await shiftApp(seen: seen(now.quality.rawValue, now.sunset), rain: false)
        #expect(same.cardShift(s2, phase: .before) == nil)
    }

    @Test func shiftAlertOffByNotifAndPhaseAndReach() async {
        let (off1, s1) = await shiftApp(seen: seen("poor", nil), rain: false,
                                        notif: .object(["all": .bool(false)]))
        #expect(off1.cardShift(s1, phase: .before) == nil)
        let (off2, s2) = await shiftApp(seen: seen("poor", nil), rain: false,
                                        notif: .object(["all": .bool(true), "wx": .bool(false)]))
        #expect(off2.cardShift(s2, phase: .before) == nil)
        // Незнакомые поля notif не мешают; по умолчанию всё включено.
        let (on, s3) = await shiftApp(seen: seen("poor", nil), rain: false, notif: .object(["srv": .bool(false)]))
        #expect(on.cardShift(s3, phase: .before) != nil)
        #expect(on.cardShift(s3, phase: .after) == nil)
        // Дальше окна прогноза снимка нет — и строки нет.
        let (far, s4) = await shiftApp(seen: seen("poor", nil), rain: false, day: 21 + 20)
        #expect(far.cardSkySnap(s4) == nil && far.cardShift(s4, phase: .before) == nil)
    }

    /// Закрыли карточку: увиденное обновилось, «сказанное» стёрто; повторно
    /// строка не звучит. Первое закрытие без памяти пишет её молча.
    @Test func closingCardWritesWhatWasSeen() async {
        var snap = Self.snap([Self.shootAt()])
        snap.extra["wxSeen"] = seen("poor", nil)
        snap.extra["wxTold"] = seen("poor", nil)
        let app = model(snap, rain: false)
        app.openCard(id: "a")
        await app.pointWeather.settled()
        let s = rec(app, "a")
        let now = app.cardSkySnap(s)!
        app.closeCard()
        #expect(app.cardShift(s, phase: .before) == nil)
        guard case .object(let told)? = app.snapshotForTests.extra["wxTold"] else { Issue.record("wxTold пропал"); return }
        #expect(told["a"] == nil)
        guard case .object(let seenNow)? = app.snapshotForTests.extra["wxSeen"], case .object(let mine)? = seenNow["a"] else {
            Issue.record("wxSeen не записан"); return
        }
        #expect(mine["q"] == .string(now.quality.rawValue))

        let fresh = model(Self.snap([Self.shootAt()]), rain: false)
        fresh.openCard(id: "a")
        await fresh.pointWeather.settled()
        fresh.closeCard()
        if case .object(let m)? = fresh.snapshotForTests.extra["wxSeen"] { #expect(m["a"] != nil) } else { Issue.record("первое закрытие не записало") }
    }

    /// Прогноз не менялся и о нём не говорили — закрытие ничего не пишет.
    @Test func closingCardWithSameForecastWritesNothing() async {
        let (probe, ps) = await shiftApp(seen: nil, rain: false)
        let now = probe.cardSkySnap(ps)!
        let (app, s) = await shiftApp(seen: seen(now.quality.rawValue, now.sunset), rain: false)
        let before = app.snapshotForTests.extra
        app.closeCard()
        #expect(app.snapshotForTests.extra == before)
        _ = s
    }
}
