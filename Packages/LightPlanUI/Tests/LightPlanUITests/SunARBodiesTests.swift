import Testing
import Foundation
import SwiftUI
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Луна, Млечный Путь, диски, стрелка и плашка входа в AR (шаг 29.8в.4).
@MainActor
struct SunARBodiesTests {

    private let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    private let barnaul = Place(latitude: 53.3548, longitude: 83.7698, zone: ZoneID("Asia/Barnaul")!)
    private let viewport = ScreenViewport(width: 393, height: 852)

    private final class MemoryBodies: ARBodiesSettings {
        var moon = false
        var milkyWay = false
        var stars = false
        var constellations = false
        var planets = false
    }
    private final class MemoryFlag: ARCalibrationFlag { var seen = true }

    private func moment(_ iso: String) -> Moment { Moment(ISO8601DateFormatter().date(from: iso)!) }

    private func model(at iso: String, now: String? = nil, bodies: MemoryBodies = MemoryBodies()) -> SunARModel {
        let clockMoment = moment(now ?? iso)
        return SunARModel(target: SunARTarget(place: tomsk, moment: moment(iso)), source: nil, camera: nil,
                          clock: { clockMoment }, calibrationFlag: MemoryFlag(), bodies: bodies)
    }

    // MARK: Метки

    @Test("диаметры: солнце 48 / 34, луна 40 / 30; метки слились — одна большего диаметра; солнце лежит выше луны")
    func diameters() throws {
        // 20 октября 21:00 по Томску: луна над горизонтом (юг, +18°), солнце глубоко под ним.
        let m = model(at: "2026-10-20T14:00:00Z", now: "2026-10-20T13:00:00Z")
        m.setMoon(true)
        let basis = CameraBasis(azimuth: 183, altitude: 18)
        let night = m.nightScene(basis: basis, optics: .typical, viewport: viewport)
        let sunScene = SunARScene.make(basis: basis, optics: .typical, viewport: viewport, arc: m.arc, sun: m.sun,
                                       now: m.sunNow, pickedIsNow: m.pickedIsNow, solar: m.solar)
        let marks = SunARMarks.make(sun: sunScene, night: night, screen: CGSize(width: 393, height: 852))
        let moonNow = try #require(marks.first { $0.id == "moon.now" })
        let moonPicked = try #require(marks.first { $0.id == "moon.picked" })
        #expect(moonNow.diameter == 40 && moonPicked.diameter == 30)
        #expect(!moonNow.isSun && !moonPicked.isSun)
        // Слились: выбранный момент = сейчас → одна метка 40.
        let merged = model(at: "2026-10-20T14:00:00Z")
        merged.setMoon(true)
        let night2 = merged.nightScene(basis: basis, optics: .typical, viewport: viewport)
        let sun2 = SunARScene.make(basis: basis, optics: .typical, viewport: viewport, arc: merged.arc, sun: merged.sun,
                                   now: merged.sunNow, pickedIsNow: merged.pickedIsNow, solar: merged.solar)
        let one = SunARMarks.make(sun: sun2, night: night2, screen: CGSize(width: 393, height: 852)).filter { !$0.isSun }
        #expect(one.count == 1 && one[0].diameter == 40 && one[0].id == "moon.now")
        // Размеры солнца — из чернил экрана: 48 «сейчас», 34 выбранный.
        #expect(SunARInk.nowLensDiameter == 48 && SunARInk.pickedLensDiameter == 34)
        #expect(SunARInk.moonNowDiameter == 40 && SunARInk.moonPickedDiameter == 30)
    }

    @Test("солнце и луна различимы не только цветом: у луны фаза и серебристый оттенок, у солнца — свет дня; лучиков нет, контур пунктиром ниже горизонта")
    func sunAndMoonDiffer() {
        let s = SunARMark(id: "sun.now", kind: .sun, center: .zero, diameter: 48, fade: 1, altitude: 40)
        let l = SunARMark(id: "moon.now", kind: .moon(illuminated: 0.5, waxing: true, limb: 0), center: .zero, diameter: 40, fade: 1)
        #expect(s.isSun && !l.isSun)
        #expect(s.kind != l.kind)
        // Солнце днём тёплое (красный выше синего), луна серебристая (синий не ниже красного).
        func rgb(_ c: Color) -> (Double, Double, Double) { UIColorBridge.rgb(c) }
        let warm = rgb(s.tint), cold = rgb(l.tint)
        #expect(warm.0 > warm.2 + 0.2)
        #expect(cold.2 >= cold.0)
        // Контур пунктиром — только у солнца под горизонтом.
        let night = SunARMark(id: "sun.now", kind: .sun, center: .zero, diameter: 48, fade: SunARMarks.ghostFade,
                              altitude: -20, belowHorizon: true)
        #expect(night.dashedContour && !s.dashedContour && !l.dashedContour)
    }

    @Test("луна под горизонтом идёт призраком 0,4, а не пропадает; над горизонтом — 1")
    func moonGhost() throws {
        let m = model(at: "2026-10-14T05:00:00Z")   // 14 октября 12:00: луна на −5°
        m.setMoon(true)
        let basis = CameraBasis(azimuth: 130, altitude: 0)
        let night = m.nightScene(basis: basis, optics: CameraOptics(longSideFOV: 100, aspect: 4.0 / 3.0), viewport: viewport)
        let picked = try #require(night.picked)
        #expect(picked.ghost)
        let sunScene = SunARScene.make(basis: basis, optics: .typical, viewport: viewport, arc: m.arc, sun: m.sun)
        let marks = SunARMarks.make(sun: sunScene, night: night, screen: CGSize(width: 393, height: 852))
        if let mark = marks.first(where: { !$0.isSun }) { #expect(mark.fade == SunARMarks.ghostFade) }
    }

    // MARK: Включатели

    @Test("включатели «Луна» и «Млечный Путь» помнятся между входами; выключенное не считается")
    func togglesAreRemembered() {
        let defaults = UserDefaults(suiteName: "sunar-bodies-\(UUID().uuidString)")!
        let first = SunARModel(target: SunARTarget(place: tomsk, moment: moment("2026-10-20T14:00:00Z")), source: nil,
                               camera: nil, calibrationFlag: MemoryFlag(), bodies: DeviceBodiesSettings(defaults: defaults))
        #expect(!first.moonOn && !first.milkyWayOn)
        let basis = CameraBasis(azimuth: 183, altitude: 18)
        let off = first.nightScene(basis: basis, optics: .typical, viewport: viewport)
        #expect(off.picked == nil && off.arc.isEmpty && off.band.isEmpty && off.core == nil)
        first.setMoon(true)
        first.setMilkyWay(true)
        let again = SunARModel(target: SunARTarget(place: tomsk, moment: moment("2026-10-20T14:00:00Z")), source: nil,
                               camera: nil, calibrationFlag: MemoryFlag(), bodies: DeviceBodiesSettings(defaults: defaults))
        #expect(again.moonOn && again.milkyWayOn)
        let on = again.nightScene(basis: basis, optics: .typical, viewport: viewport)
        #expect(on.picked != nil && !on.arc.isEmpty && on.milkyWayOn)
        again.setMoon(false)
        #expect(!DeviceBodiesSettings(defaults: defaults).moon && DeviceBodiesSettings(defaults: defaults).milkyWay)
    }

    @Test("Млечный Путь днём — призрак, ночью — полный; ядро — из ядра (MilkyWay.corePosition)")
    func milkyWayGhostAndCore() throws {
        let night = model(at: "2026-08-20T15:00:00Z")   // 22:00 в Томске, солнце −9°
        night.setMilkyWay(true)
        let core = MilkyWay.corePosition(date: night.day, minutes: night.minutes, place: tomsk, time: .iau)
        let basis = CameraBasis(azimuth: core.azimuth, altitude: max(core.altitude, 5))
        let scene = night.nightScene(basis: basis, optics: .typical, viewport: viewport)
        #expect(scene.coreAzimuth == core.azimuth && scene.coreAltitude == core.altitude)
        #expect(scene.milkyWayOn)
        // Для солнца −9° полоса ещё призрак (порог −6° выше −9°? нет: −9° ниже порога — тёмное небо).
        #expect(!scene.skyGhost)
        let day = model(at: "2026-08-20T05:00:00Z")      // 12:00, солнце высоко
        day.setMilkyWay(true)
        let dayScene = day.nightScene(basis: basis, optics: .typical, viewport: viewport)
        #expect(dayScene.skyGhost)
    }

    // MARK: Кадр и диски

    @Test("соответствие окна и кадра: центр окна — центр кадра; вправо по окну — вверх по датчику")
    func frameMappingCenterAndTurn() throws {
        let view = CGSize(width: 393, height: 852)
        let buffer = CGSize(width: 1440, height: 1080)
        let m = ARFrameMapping.aspectFillPortrait(view: view, buffer: buffer)
        let c = m.uv(at: CGPoint(x: view.width / 2, y: view.height / 2))
        #expect(abs(c.x - 0.5) < 1e-9 && abs(c.y - 0.5) < 1e-9)
        // Вправо по окну (портрет) — к верху датчика: v убывает; вниз по окну — к правому краю датчика: u растёт.
        let right = m.uv(at: CGPoint(x: view.width / 2 + 40, y: view.height / 2))
        let down = m.uv(at: CGPoint(x: view.width / 2, y: view.height / 2 + 40))
        #expect(right.y < c.y && abs(right.x - c.x) < 1e-9)
        #expect(down.x > c.x && abs(down.y - c.y) < 1e-9)
        // «Заполнить»: окно 393×852 из портретного кадра 1080×1440 — по высоте весь кадр, по ширине срез.
        let top = m.uv(at: CGPoint(x: view.width / 2, y: 0))
        let bottom = m.uv(at: CGPoint(x: view.width / 2, y: view.height))
        #expect(abs(top.x - 0) < 1e-6 && abs(bottom.x - 1) < 1e-6)
    }

    @Test("соответствие по трём точкам превью: аффинное, вырожденное (превью не запущено) — отказ")
    func frameMappingFromSamples() throws {
        let view = CGSize(width: 400, height: 800)
        let m = try #require(ARFrameMapping.fromSamples(view: view, origin: CGPoint(x: 0.2, y: 1),
                                                        right: CGPoint(x: 0.2, y: 0), bottom: CGPoint(x: 1, y: 1)))
        let mid = m.uv(at: CGPoint(x: 200, y: 400))
        #expect(abs(mid.x - 0.6) < 1e-9 && abs(mid.y - 0.5) < 1e-9)
        #expect(ARFrameMapping.fromSamples(view: view, origin: .zero, right: .zero, bottom: .zero) == nil)
        #expect(ARFrameMapping.fromSamples(view: .zero, origin: .zero, right: CGPoint(x: 1, y: 0), bottom: CGPoint(x: 0, y: 1)) == nil)
    }

    @Test("гнущая кромка: 9 pt у диска 48, 7,5 pt у 30, не больше четверти диаметра; сдвиг у края 8 pt")
    func rim() {
        #expect(SunARInk.rim(for: 48) == 9)
        #expect(SunARInk.rim(for: 30) == 7.5)
        #expect(SunARInk.rim(for: 20) == 5)
        #expect(SunARInk.lensShift == 8)
    }

    // MARK: Плашка входа

    private final class EntryLocator: DeviceLocating {
        var fix: DeviceFix
        var authorized: Bool
        var asks: Bool
        private(set) var calls = 0
        init(fix: DeviceFix, authorized: Bool = false, needsPermission: Bool = false) {
            self.fix = fix; self.authorized = authorized; self.asks = needsPermission
        }
        func currentFix() async -> DeviceFix { calls += 1; return fix }
        var isAlreadyAuthorized: Bool { authorized }
        var needsPermission: Bool { asks }
    }
    private struct QuietGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCity: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private struct NoWx: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }

    private func app(_ locator: EntryLocator) -> AppModel {
        AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                 locator: locator, geocoder: QuietGeocoder(), cityLookup: NoCity(), weatherSource: NoWx())
    }

    private let moscowFix = GeoCoordinate(latitude: 55.7558, longitude: 37.6173)
    private let barnaulFix = GeoCoordinate(latitude: 53.3548, longitude: 83.7698)
    private let when = Moment(ISO8601DateFormatter().date(from: "2026-10-20T14:00:00Z")!)

    @Test("геолокация не спрашивалась — плашка «выключена»; отказана — «нет доступа»; AR не открыт")
    func entryWhenLocationOffOrDenied() {
        let a = app(EntryLocator(fix: .unavailable, authorized: false, needsPermission: true))
        a.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        #expect(a.sunAR == nil)
        #expect(a.sunAREntry?.reason == .off && a.sunAREntry?.name == "Барнаул")
        let b = app(EntryLocator(fix: .denied, authorized: false, needsPermission: false))
        b.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        #expect(b.sunAR == nil && b.sunAREntry?.reason == .denied)
    }

    /// Ждёт, пока модель войдёт в состояние (ответ телефона идёт через `await`).
    private func settle(_ a: AppModel, until done: @MainActor () -> Bool) async throws {
        for _ in 0..<240 where !done() { try await Task.sleep(for: .milliseconds(25)) }
    }

    @Test("телефон дальше 50 км от выбранного места — плашка с расстоянием; рядом — AR открывается сразу, без плашки")
    func entryWhenFarOrNear() async throws {
        let far = app(EntryLocator(fix: .fix(moscowFix), authorized: true))
        far.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        try await settle(far) { far.sunAREntry != nil }
        #expect(far.sunAR == nil)
        if case .far(let km)? = far.sunAREntry?.reason { #expect(km > 2500 && km < 3500) } else { Issue.record("нет плашки «далеко»") }
        let near = app(EntryLocator(fix: .fix(barnaulFix), authorized: true))
        near.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        try await settle(near) { near.sunAR != nil }
        #expect(near.sunAREntry == nil)
        #expect(near.sunAR != nil)
    }

    @Test("решение — по свежей точке, не по старой: старая рядом с выбранным, свежая далеко — плашка, AR не открыт")
    func entryUsesFreshFix() async throws {
        let locator = EntryLocator(fix: .fix(barnaulFix), authorized: true)
        let a = app(locator)
        _ = await a.locateHere()                 // старая точка телефона — рядом с выбранным местом
        try await Task.sleep(for: .milliseconds(200))
        let stale = try #require(a.phoneSpot())
        #expect(abs(stale.longitude - barnaulFix.longitude) < 1e-6)
        locator.fix = .fix(moscowFix)            // телефон уже в Москве
        a.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        try await settle(a) { a.sunAREntry != nil || a.sunAR != nil }
        #expect(a.sunAR == nil)
        if case .far? = a.sunAREntry?.reason {} else { Issue.record("плашки «далеко» нет: \(String(describing: a.sunAREntry))") }
    }

    private final class SlowLocator: DeviceLocating {
        private var waiter: CheckedContinuation<DeviceFix, Never>?
        func currentFix() async -> DeviceFix { await withCheckedContinuation { waiter = $0 } }
        var isAlreadyAuthorized: Bool { true }
        var pending: Bool { waiter != nil }
        func answer(_ fix: DeviceFix) { waiter?.resume(returning: fix); waiter = nil }
    }

    @Test("ответ телефона пришёл после того, как плашку закрыли: ничего не меняется, AR не открывается")
    func lateAnswerIsIgnored() async throws {
        let slow = SlowLocator()
        let a = AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                         locator: slow, geocoder: QuietGeocoder(), cityLookup: NoCity(), weatherSource: NoWx())
        a.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        // Телефон молчит дольше 0,4 с: плашка «Определяю место…». Ждём состояние, а не срок: под нагрузкой
        // очередь главного актора отстаёт на десятки миллисекунд.
        try await settle(a) { a.sunAREntry?.reason == .locating && slow.pending }
        #expect(a.sunAREntry?.reason == .locating)
        a.dismissSunAREntry()
        slow.answer(.fix(moscowFix))
        try await Task.sleep(for: .milliseconds(150))
        #expect(a.sunAREntry == nil && a.sunAR == nil)
        // И отказ после закрытия — тоже в пустоту.
        a.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        try await settle(a) { slow.pending }
        #expect(slow.pending)
        a.dismissSunAREntry()
        slow.answer(.denied)
        try await Task.sleep(for: .milliseconds(150))
        #expect(a.sunAREntry == nil && a.sunAR == nil)
    }

    /// Телефон, который отвечает по одному запросу за раз и в нужном порядке: запросы стоят в очереди.
    private final class QueueLocator: DeviceLocating {
        private var waiters: [CheckedContinuation<DeviceFix, Never>] = []
        /// Сколько ответов уже вышло из `currentFix` к вызывающему.
        private(set) var delivered = 0
        func currentFix() async -> DeviceFix {
            let fix = await withCheckedContinuation { waiters.append($0) }
            delivered += 1
            return fix
        }
        var isAlreadyAuthorized: Bool { true }
        var asked: Int { waiters.count }
        func answer(_ index: Int, _ fix: DeviceFix) { waiters[index].resume(returning: fix) }
    }

    @Test("ответ старого запроса геопозиции не снимает занятость нового нажатия (шаг 29.8в.6, ревью GPT)")
    func staleAnswerKeepsNewEntryBusy() async throws {
        let queue = QueueLocator()
        let a = AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                         locator: queue, geocoder: QuietGeocoder(), cityLookup: NoCity(), weatherSource: NoWx())
        // Вход 1: плашка «Определяю место…» (телефон молчит); вход спрашивает телефон сам, и их запросов может быть больше
        // одного — счёт ведём не по номерам, а по тому, что стало после каждого шага.
        a.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        try await settle(a) { a.sunAREntry?.reason == .locating }
        let beforeFirstPress = queue.asked
        a.sunARUseMyLocation()
        try await settle(a) { queue.asked > beforeFirstPress }
        #expect(queue.asked > beforeFirstPress, "нажатие не дошло до телефона")
        #expect(a.sunAREntryBusy)
        // Всё, что спрошено к этой минуте, — запросы входа 1: их ответы придут «поздно».
        let oldRequests = queue.asked
        // Плашку закрыли и открыли снова (вход 2), нажали ещё раз — замок нового нажатия взят.
        a.dismissSunAREntry()
        #expect(!a.sunAREntryBusy)
        a.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        try await settle(a) { a.sunAREntry?.reason == .locating }
        let beforeSecondPress = queue.asked
        a.sunARUseMyLocation()
        try await settle(a) { queue.asked > beforeSecondPress }
        #expect(queue.asked > beforeSecondPress, "второе нажатие не дошло до телефона")
        #expect(a.sunAREntryBusy)
        // Запросы входа 1 отвечают поздно: у входа 2 замок остаётся — до этого шага он снимался.
        for i in 0..<oldRequests { queue.answer(i, .denied) }
        // Ответ выходит из локатора на фоновом потоке и возвращается на главный актор позже: ждём выхода, затем
        // даём ему время дойти (как в `lateAnswerIsIgnored`: проверка «ничего не изменилось» без наблюдаемого события).
        try await settle(a) { queue.delivered == oldRequests }
        try await Task.sleep(for: .milliseconds(300))
        #expect(a.sunAREntryBusy, "старый ответ снял занятость нового входа")
        #expect(a.sunAREntry != nil)
        // Ответы входа 2 замок снимают.
        for i in oldRequests..<queue.asked { queue.answer(i, .denied) }
        try await settle(a) { !a.sunAREntryBusy && a.sunAREntry?.reason == .denied }
        #expect(a.sunAREntry?.reason == .denied)
    }

    @Test("«Использовать моё местоположение»: точка есть — AR по телефону, место приложения не тронуто; отказ — плашка снова с пояснением")
    func entryUseMine() async throws {
        let granted = app(EntryLocator(fix: .fix(moscowFix), authorized: true))
        _ = await granted.locateHere()
        granted.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        try await settle(granted) { granted.sunAREntry != nil }
        #expect(granted.sunAREntry != nil)
        let appPlace = granted.light.timebar.place
        granted.sunARUseMyLocation()
        for _ in 0..<80 where granted.sunAR == nil { try await Task.sleep(for: .milliseconds(25)) }
        let target = try #require(granted.sunAR)
        if case .phone(let p, let far) = target.choice {
            #expect(abs(p.latitude - 55.7558) < 1e-6 && far == nil)
        } else { Issue.record("AR открыт не по телефону") }
        #expect(granted.sunAREntry == nil)
        #expect(granted.light.timebar.place == appPlace)

        let refuse = EntryLocator(fix: .denied, authorized: false, needsPermission: true)
        let denied = app(refuse)
        denied.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        denied.sunARUseMyLocation()
        for _ in 0..<80 where refuse.calls == 0 || denied.sunAREntryBusy { try await Task.sleep(for: .milliseconds(25)) }
        #expect(denied.sunAR == nil)
        #expect(denied.sunAREntry?.reason == .denied)
        #expect(denied.sunAREntry?.name == "Барнаул")
    }

    @Test("«Оставить «Барнаул»»: AR считает для выбранного места, плашка уходит, место приложения не меняется")
    func entryKeep() throws {
        let a = app(EntryLocator(fix: .unavailable, authorized: false, needsPermission: true))
        let appPlace = a.light.timebar.place
        a.beginSunAR(chosen: barnaul, name: "Барнаул", moment: when)
        a.sunARKeepChosen()
        #expect(a.sunAREntry == nil)
        let t = try #require(a.sunAR)
        #expect(t.choice == .chosen(barnaul) && t.moment == when)
        #expect(a.light.timebar.place == appPlace)
    }
}

/// Цвет SwiftUI → красный, зелёный, синий (`0…1`) для проверки оттенка.
private enum UIColorBridge {
    static func rgb(_ c: Color) -> (Double, Double, Double) {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #else
        return (1, 0.76, 0.3)
        #endif
    }
}
#if canImport(UIKit)
import UIKit
#endif
