import Foundation
import Testing
import LightPlanCore
@testable import LightPlanUI
import LightPlanMapCanvas

/// Свод карты (итерация 20б, заполнение `.map-fold` в `renderMap` веба):
/// какие строки есть в каком режиме и когда строка молчит отсутствием.
struct MapSummaryTests {
    let lexicon = Lexicon("ru")
    let clock = ClockText(language: "ru", preference: .h24)
    let date = CivilDate(year: 2026, month: 9, day: 23)
    let place = Place(latitude: 55.75, longitude: 37.62, zone: ZoneID(fixedOffsetHours: 3))

    func build(_ t: Minutes, pro: Bool, mw: Bool = false, glow: Double? = nil, day: CivilDate? = nil) -> MapSummary {
        let d = day ?? date
        let sun = SolarDay(date: d, place: place)
        let input = mw ? MapSummary.MilkyWayInput(
            window: MilkyWayWindow(date: d, place: place), moon: MoonVsStars(date: d, place: place), sky: nil,
            nextDark: { nil }) : nil
        return MapSummary.build(date: d, t: t, sun: sun, place: place, utcOffset: 3, pro: pro, glow: glow, mw: input,
                                dateShort: { "\($0.day).\($0.month)" }, lexicon: lexicon, clock: clock)
    }

    func labels(_ s: MapSummary) -> [String] { s.rows.map(\.label) }

    @Test("Просто днём: окна света, луна, точка, ближайшее — без измерений астро")
    func simpleDay() {
        let s = build(13 * 60, pro: false)
        #expect(labels(s) == ["map.golden", "map.blue", "map.moon", "map.spot", "map.next"])
        #expect(s.rows.first { $0.label == "map.spot" }?.tone == .warm)
    }

    @Test("Астро днём: свет идёт, высота, тень — первыми, в порядке разметки")
    func proDay() {
        let s = build(13 * 60, pro: true)
        #expect(Array(labels(s).prefix(3)) == ["map.lightFrom", "map.sunElev", "map.shadow"])
        #expect(!labels(s).contains("map.twilight"))
        #expect(s.rows[1].text.hasPrefix("+"))
    }

    @Test("Ночь: точки съёмки нет, света нет; сумерки — только в свои часы")
    func night() {
        let sun = SolarDay(date: date, place: place)
        let deep = build(sun.solarNoon + 12 * 60, pro: true)
        #expect(!labels(deep).contains("map.spot"))
        #expect(!labels(deep).contains("map.lightFrom"))
        // Середина навигационных сумерек вечером — ступень и отсчёт до конца.
        let mid = (sun.civilB! + sun.nauticalB!) / 2
        #expect(labels(build(mid, pro: true)).contains("map.twilight"))
        #expect(!labels(build(mid, pro: false)).contains("map.twilight"))
        // В тестах словарь без ресурсов отдаёт ключи — видна ветка ступени.
        #expect(MapSummary.twilight(sun: sun, t: mid, lexicon: lexicon, clock: clock) == "twi.till")
    }

    @Test("Слой Млечного Пути добавляет пять строк в конец и группу в «Подробно»")
    func milkyWay() {
        let off = build(22 * 60, pro: true)
        let on = build(22 * 60, pro: true, mw: true, glow: 3.2)
        #expect(labels(on).last == "map.verdict")
        #expect(labels(on).contains("map.glow"))
        #expect(on.pro.count == off.pro.count + 1)
        let group = on.pro.first { $0.title == lexicon.t("mpro.mw") }
        #expect(group?.rows.last?.label == lexicon.t("mpro.glow"))
    }

    @Test("Затмение: строка свода только в тот самый день; ближайшее — последней группой")
    func eclipse() {
        let day = EclipseTable.all.first!.date
        let s = build(12 * 60, pro: false, day: day)
        #expect(s.rows.first { $0.label == "map.eclipse" }?.tone == .terra)
        #expect(s.pro.last?.rows.first?.value == lexicon.t("mpro.eclToday"))
        #expect(!labels(build(12 * 60, pro: false)).contains("map.eclipse") || EclipseTable.on(date) != nil)
    }

    @Test("Ближайшее за полночью — завтрашнее событие; отсчёт часами и минутами")
    func nextAndGap() {
        let sun = SolarDay(date: date, place: place)
        let nx = MapSummary.nextEvent(sun: sun, t: sun.astroB! + 1, lexicon: lexicon)!
        #expect(nx.minute == sun.astroA! + 1440)
        #expect(MapSummary.gap(18.4, lexicon: lexicon) == lexicon.t("gap.minutes", ["m": "18"]))
        #expect(MapSummary.gap(252, lexicon: lexicon) == "4:12")
        #expect(MapSummary.gap(61, lexicon: lexicon) == "1:01")
        #expect(MapSummary.jsNumber(5.5) == "5.5" && MapSummary.jsNumber(3) == "3")
    }
}

/// Меню слоёв (итерация 20б): пункт переключает свой слой, снимок получает
/// все пять ключей, как `saveAll` веба, и читается обратно тем же.
struct MapLayersTests {
    @Test("Переключение слоя и запись в снимок — туда и обратно")
    func roundTrip() {
        var l = MapLayers(nil)
        #expect(l[.sun] && l[.moon] && !l[.mw] && l[.compass] && l[.spots])
        l[.mw] = true
        l[.sun] = false
        #expect(l.saved.count == 5)
        #expect(MapLayers(l.saved) == l)
    }
}

/// Подписи холста (20б): `nameKey` и `build({labels, lang})` веба.
struct MapStyleLabelsTests {
    @Test(arguments: [("ru", "name:ru"), ("en-GB", "name:en"), ("es", "name:en"), ("ja", "name:ja"), ("zh", "name:zh")])
    func nameKey(code: String, key: String) { #expect(MapStyle.nameKey(code) == key) }

    @Test("Символьные слои видны и пишут имя на языке, прочие не тронуты")
    func patch() throws {
        let src = #"{"layers":[{"id":"land","type":"fill"},{"id":"roadname_pri","type":"symbol","layout":{"text-field":"{name}","visibility":"none"}},{"id":"place_dot","type":"symbol"}]}"#
        let out = try #require(MapStyle.patch(Data(src.utf8), labels: true, key: "name:ru"))
        let layers = try #require((try JSONSerialization.jsonObject(with: out) as? [String: Any])?["layers"] as? [[String: Any]])
        #expect(layers[0]["layout"] == nil)
        let road = try #require(layers[1]["layout"] as? [String: Any])
        #expect(road["visibility"] as? String == "visible")
        let field = try #require(road["text-field"] as? [Any])
        #expect(field.count == 3 && field[0] as? String == "coalesce")
        #expect((field[1] as? [String]) == ["get", "name:ru"])
        #expect((layers[2]["layout"] as? [String: Any])?["text-field"] == nil)
        #expect((layers[2]["layout"] as? [String: Any])?["visibility"] as? String == "visible")
    }
}
