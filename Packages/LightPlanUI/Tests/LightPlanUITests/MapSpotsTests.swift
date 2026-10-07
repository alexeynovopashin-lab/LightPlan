import Testing
import Foundation
import CoreGraphics
@testable import LightPlanUI
import LightPlanMapCanvas
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 20б, сохранённые точки: проекция булавок, попадание тапа,
/// закладка шапки, имя и удаление — как у веба (`mapSave`, `commitSpotName`,
/// `spotNameDel`, `spotAtPoint`).
@MainActor
struct MapSpotsTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class Locator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func model(_ snapshot: Snapshot = Snapshot()) -> AppModel {
        AppModel(snapshot: snapshot, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Tomsk")!,
                 locator: Locator(), geocoder: SilentGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
    }

    // MARK: - Проекция

    /// Сдвиг булавки меркатором и мера `metersPerPoint` — одна плитка 512:
    /// 0,01° к востоку в Томске на уровне 14 — столько метров, сколько точек
    /// кадра × метров на точку. Север — вверх (y меньше).
    @Test func projectionAgreesWithMetersPerPoint() {
        let cam = MapCanvasCamera(center: MapCanvasCenter(latitude: 56.4846, longitude: 84.9476), zoom: 14)
        #expect(MapSpots.offset(latitude: 56.4846, longitude: 84.9476, camera: cam) == .zero)
        let east = MapSpots.offset(latitude: 56.4846, longitude: 84.9576, camera: cam)
        let meters = 0.01 * .pi / 180 * 6_378_137 * cos(56.4846 * .pi / 180)
        let perPoint = MapCanvasView.metersPerPoint(zoom: 14, latitude: 56.4846)
        #expect(abs(Double(east.x) - meters / perPoint) < 0.01)
        #expect(abs(east.y) < 1e-9)
        let north = MapSpots.offset(latitude: 56.4946, longitude: 84.9476, camera: cam)
        #expect(north.y < -40 && north.x == 0)
        // Уровень выше на единицу — вдвое дальше.
        var z15 = cam; z15.zoom = 15
        #expect(abs(MapSpots.offset(latitude: 56.4846, longitude: 84.9576, camera: z15).x - east.x * 2) < 1e-6)
    }

    /// Порча: без поправки широты (тайл как на экваторе) Томск уехал бы.
    @Test func projectionIsNotEquirectangular() {
        let cam = MapCanvasCamera(center: MapCanvasCenter(latitude: 56.4846, longitude: 84.9476), zoom: 14)
        let north = MapSpots.offset(latitude: 56.4946, longitude: 84.9476, camera: cam)
        let flat: Double = 0.01 / 360 * 512 * pow(2.0, 14.0)
        #expect(abs(-Double(north.y) - flat) > 10)
    }

    // MARK: - Попадание тапа

    @Test func tapHitsBodyOrLabelNearestFirst() {
        let a = (id: "a", tip: CGPoint(x: 100, y: 100), labelWidth: CGFloat(60))
        let b = (id: "b", tip: CGPoint(x: 108, y: 104), labelWidth: CGFloat(60))
        // Тело: 20 × 25,7 от (−10, −25,7), поле 6.
        #expect(MapSpots.hit(CGPoint(x: 100, y: 92), marks: [a]) == "a")
        #expect(MapSpots.hit(CGPoint(x: 85, y: 92), marks: [a]) == "a")        // в поле 6
        #expect(MapSpots.hit(CGPoint(x: 83, y: 92), marks: [a]) == nil)
        // Подпись: от (14, −23,2), ширина 60, высота 15, поле 4.
        #expect(MapSpots.hit(CGPoint(x: 160, y: 90), marks: [a]) == "a")
        #expect(MapSpots.hit(CGPoint(x: 179, y: 90), marks: [a]) == nil)
        // Внахлёст — ближняя к центру задетой части.
        #expect(MapSpots.hit(CGPoint(x: 101, y: 92), marks: [a, b]) == "a")
        #expect(MapSpots.hit(CGPoint(x: 109, y: 96), marks: [a, b]) == "b")
        // Подпись ещё не измерена — попадает только тело.
        let c = (id: "c", tip: CGPoint(x: 100, y: 100), labelWidth: CGFloat(0))
        #expect(MapSpots.hit(CGPoint(x: 140, y: 90), marks: [c]) == nil)
    }

    /// Головка булавки — 20 pt, как центр компаса (13 + кольца 2 × 3,5).
    @Test func pinHeadMatchesCompassCentre() {
        #expect(MapSpots.headDiameter == 13 + 2 * 3.5)
        #expect(abs(14 * MapSpots.glyphScale - MapSpots.headDiameter) < 1e-9)
    }

    @Test func offScreenBoundsMatchWeb() {
        let s = CGSize(width: 900, height: 900)
        #expect(MapSpots.onScreen(CGPoint(x: -140, y: -80), in: s))
        #expect(!MapSpots.onScreen(CGPoint(x: -141, y: 0), in: s))
        #expect(!MapSpots.onScreen(CGPoint(x: 0, y: 981), in: s))
    }

    // MARK: - Знаки под ротором (28п)

    /// Остриё точки при курсе 0 / 90 / 180 / 270°: карта крутится навстречу
    /// телефону. Точка к востоку от оси при курсе 90° (смотрим на восток)
    /// уходит вверх экрана, к северу — влево.
    @Test func screenTipFollowsTheRotor() {
        let axis = CGPoint(x: 220, y: 400), d = CGPoint(x: 60, y: -40)
        func tip(_ a: Double) -> CGPoint { MapSpots.screenTip(offset: d, axis: axis, angle: a) }
        func near(_ p: CGPoint, _ x: Double, _ y: Double) -> Bool { abs(p.x - x) < 1e-9 && abs(p.y - y) < 1e-9 }
        #expect(near(tip(0), 280, 360))
        #expect(near(tip(90), 180, 340))
        #expect(near(tip(180), 160, 440))
        #expect(near(tip(270), 260, 460))
        #expect(near(MapSpots.screenTip(offset: CGPoint(x: 60, y: 0), axis: axis, angle: 90), 220, 340))   // восток — вверх
        #expect(near(MapSpots.screenTip(offset: CGPoint(x: 0, y: -40), axis: axis, angle: 90), 180, 400))  // север — влево
    }

    /// Остриё идёт по кругу вокруг оси: расстояние до неё на любом курсе то же,
    /// и угол поворота — ровно минус курс.
    @Test func screenTipKeepsDistanceAndTurnsByMinusHeading() {
        let axis = CGPoint(x: 220, y: 433.5), d = CGPoint(x: 83.4, y: -17.9)
        let r0 = hypot(d.x, d.y)
        for a in stride(from: 0.0, through: 360.0, by: 7.5) {
            let t = MapSpots.screenTip(offset: d, axis: axis, angle: a)
            #expect(abs(hypot(t.x - axis.x, t.y - axis.y) - r0) < 1e-9)
            let turn = atan2(t.y - axis.y, t.x - axis.x) - atan2(d.y, d.x)
            let want = -a * .pi / 180
            #expect(abs(sin(turn - want)) < 1e-9 && cos(turn - want) > 0)
        }
    }

    /// Плашка идёт за остриём, но не крутится: от повёрнутого острия она всегда
    /// на (14; −23,2) тех же размеров, а тап по месту, куда плашка уехала бы
    /// вместе с картой, её не задевает — в этом месте пусто.
    @Test func plateStaysUprightAtEveryHeading() {
        let axis = CGPoint(x: 220, y: 400), d = CGPoint(x: 70, y: -45), w: CGFloat = 90
        for a in [0.0, 33, 90, 135, 180, 270, 315, 359] {
            let tip = MapSpots.screenTip(offset: d, axis: axis, angle: a)
            let mark = (id: "a", tip: tip, labelWidth: w)
            let upright = CGPoint(x: tip.x + MapSpots.labelOrigin.x + w / 2, y: tip.y + MapSpots.labelOrigin.y + MapSpots.labelHeight / 2)
            #expect(MapSpots.hit(upright, marks: [mark]) == "a")
            // Правый край и верх плашки — те же при любом курсе.
            #expect(MapSpots.hit(CGPoint(x: tip.x + MapSpots.labelOrigin.x + w + 3, y: upright.y), marks: [mark]) == "a")
            #expect(MapSpots.hit(CGPoint(x: tip.x + MapSpots.labelOrigin.x + w + 5, y: upright.y), marks: [mark]) == nil)
            #expect(MapSpots.hit(CGPoint(x: upright.x, y: tip.y + MapSpots.labelOrigin.y - 5), marks: [mark]) == nil)
        }
        // Повёрнутая вместе с картой плашка (прежний вид) при курсе 90° стояла бы
        // над остриём — там теперь пусто.
        let tip = MapSpots.screenTip(offset: d, axis: axis, angle: 90)
        #expect(MapSpots.hit(CGPoint(x: tip.x, y: tip.y - 14 - w / 2), marks: [(id: "a", tip: tip, labelWidth: w)]) == nil)
    }

    // MARK: - Закладка, имя, удаление

    @Test func bookmarkSavesPlaceUnderPinThenRemovesIt() {
        let app = model()
        app.moveFromMap(latitude: 56.484612, longitude: 84.947634)
        #expect(app.spotHere == nil)
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let sp = app.toggleSpotHere(now: at)
        #expect(sp != nil)
        #expect(app.spots.count == 1)
        let s = app.spots[0]
        // Имени от геокодера нет — координаты, и геокодер ещё может назвать.
        #expect(s.name == "56.485 N · 84.948 E")
        #expect(s.named == false && s.pinned == true)
        #expect(s.latitude == 56.48461 && s.longitude == 84.94763)
        #expect(s.id.hasPrefix("p" + String(Int64(1_790_000_000_000), radix: 36)) && s.id.count == 1 + 8 + 4)
        #expect(s.modifiedAt == 1_790_000_000_000)
        #expect(app.spotHere?.id == s.id)
        // ~60 м в сторону — всё ещё та же точка.
        app.moveFromMap(latitude: 56.4851, longitude: 84.9481)
        #expect(app.spotHere?.id == s.id)
        #expect(app.toggleSpotHere(now: at) == nil)
        #expect(app.spots.isEmpty)
    }

    @Test func renameTrimsAndMarksNamed() {
        let app = model()
        app.moveFromMap(latitude: 38.643, longitude: 34.828)
        let sp = app.toggleSpotHere()!
        app.renameSpot(id: sp.id, to: "   ")
        #expect(app.spots[0].name == sp.name && app.spots[0].named == false)
        app.renameSpot(id: sp.id, to: "  Долина любви \n")
        #expect(app.spots[0].name == "Долина любви" && app.spots[0].named == true)
    }

    /// Удаление: ссылки маршрутов съёмок обнуляются, могила — в `graves`,
    /// повторная могила того же id заменяет прежнюю.
    @Test func removeUnlinksRoutesAndBuries() {
        var snap = Snapshot()
        var spot = Spot(id: "pX", name: "Парк", latitude: 56.47, longitude: 84.95)
        spot.pinned = true
        snap.spots = [spot, Spot(id: "pY", name: "Лофт", latitude: 56.49, longitude: 84.97)]
        var s = Session(id: "s1", day: CivilDate(year: 2026, month: 10, day: 3), start: 600)
        s.route = [RoutePoint(start: 600, name: "Парк", spotId: "pX"), RoutePoint(start: 660, name: "Лофт", spotId: "pY")]
        snap.sessions = [s]
        snap.extra["graves"] = .array([.object(["id": .string("pX"), "del": .number(1)])])
        let app = model(snap)
        app.removeSpot(id: "pX", now: Date(timeIntervalSince1970: 2))
        #expect(app.spots.map(\.id) == ["pY"])
        let out = app.snapshotForTests
        #expect(out.sessions[0].route.map(\.spotId) == [nil, "pY"])
        #expect(out.extra["graves"] == .array([.object(["id": .string("pX"), "del": .number(2000)])]))
    }

    @Test(arguments: [
        ([], "Томск"),
        (["Томск"], "Томск 2"),
        (["Томск", "Томск 2", "Томск 02"], "Томск 3"),
        (["Томск 5"], "Томск 6"),
        (["Томск-2", "Томск a"], "Томск"),
    ] as [([String], String)])
    func uniqueNameLikeWeb(existing: [String], expected: String) {
        let spots = existing.enumerated().map { Spot(id: "\($0.offset)", name: $0.element, latitude: 0, longitude: 0) }
        #expect(AppModel.uniqueSpotName("Томск", in: spots) == expected)
    }

    /// Поля веба `pinned`, `named`, `ic` переживают чтение-запись: импорт
    /// ничего не удаляет (правило итерации 12), а заливка булавки от `pinned`.
    @Test func spotKeepsWebFields() throws {
        let json = #"{"id":"p1","name":"Поляна","lat":56.1,"lon":84.2,"pinned":true,"named":true,"ic":"tree"}"#
        let sp = try JSONDecoder().decode(Spot.self, from: Data(json.utf8))
        #expect(sp.pinned == true && sp.named == true && sp.icon == "tree")
        let back = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sp)) as! [String: Any]
        #expect(back["pinned"] as? Bool == true && back["named"] as? Bool == true && back["ic"] as? String == "tree")
        // Нет ключа — нет и в записи: адресная точка веба не становится «пальцевой».
        let bare = try JSONDecoder().decode(Spot.self, from: Data(#"{"id":"p2","lat":1,"lon":2}"#.utf8))
        let bareBack = try JSONSerialization.jsonObject(with: JSONEncoder().encode(bare)) as! [String: Any]
        #expect(bareBack["pinned"] == nil && bareBack["named"] == nil && bareBack["ic"] == nil)
    }
}
