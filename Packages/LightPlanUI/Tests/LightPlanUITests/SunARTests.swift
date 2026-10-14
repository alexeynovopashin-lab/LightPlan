import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData

/// Слой AR (шаг 29.8в): модель экрана и контраст чернил.
@MainActor
struct SunARTests {

    /// Источник, которым тест сам подаёт отсчёты.
    private final class Feed: AttitudeSource {
        var isAvailable = true
        var north: AttitudeNorth? = .trueNorth
        var push: (@MainActor (AttitudeSample) -> Void)?
        func start(_ onSample: @escaping @MainActor (AttitudeSample) -> Void) { push = onSample }
        func stop() { push = nil }
    }

    private let barnaul = Place(latitude: 53.3548, longitude: 83.7698, zone: ZoneID("Asia/Barnaul")!)
    private func target(_ iso: String) -> SunARTarget {
        SunARTarget(place: barnaul, moment: Moment(ISO8601DateFormatter().date(from: iso)!))
    }

    // MARK: - Контраст (числами, по константам, что рисует экран)

    @Test("контраст светлого на тёмной подложке: на белом, сером и чёрном фоне не ниже 4,5 (текст) и 3 (линия)")
    func inkContrast() {
        let plate = SunARInk.plateOpacity
        var lines: [String] = []
        for (name, bg) in [("белый", 1.0), ("серый", 0.5), ("чёрный", 0.0)] {
            let text = SunARInk.contrast(onBackground: bg, plate: plate)
            let outline = SunARInk.outlineContrast(onBackground: bg, plate: SunARInk.outlineOpacity)
            // Линия отделима от фона либо обводкой, либо самой белой жилой: берём лучшее из двух.
            let core = (SunARInk.luminance(1) + 0.05) / (SunARInk.luminance(bg) + 0.05)
            let line = max(outline, core)
            lines.append(String(format: "%@: текст/подложка %.2f, обводка/фон %.2f, жила/фон %.2f", name, text, outline, core))
            #expect(text >= 4.5, "\(name): текст \(text)")
            #expect(line >= 3, "\(name): линия \(line)")
        }
        print("SUNAR_CONTRAST " + lines.joined(separator: " | "))
    }

    // MARK: - Модель

    @Test("ползунок: маркер сцены идёт по дуге — на минуте точки дуги он ровно в ней, день не меняется")
    func sliderWalksTheArc() throws {
        let m = SunARModel(target: target("2026-09-23T06:00:00Z"), source: nil)
        let day = m.day
        let viewport = ScreenViewport(width: 393, height: 852)
        let basis = CameraBasis(azimuth: 190, altitude: 40)
        var xs: [Double] = []
        for minute in [660.0, 720, 780, 840] {
            m.set(minutes: minute)
            let scene = SunARScene.make(basis: basis, optics: .typical, viewport: viewport, arc: m.arc, sun: m.sun)
            let p = try #require(scene.marker)
            xs.append(p.x)
            // Та же точка в списке дуги (шаг 10 минут, минута кратна 10).
            let s = try #require(m.arc.first { $0.minutes == minute })
            let q = try #require(SkyProjection.project(azimuth: s.azimuth, altitude: s.apparentAltitude, basis: basis,
                                                       optics: .typical, viewport: viewport))
            #expect(abs(p.x - q.x) < 1e-6 && abs(p.y - q.y) < 1e-6)
        }
        #expect(m.day == day)
        // Днём солнце идёт по азимуту вправо: x растёт с временем (камера на юг).
        #expect(xs == xs.sorted())
    }

    @Test("«Сейчас»: цель — сегодняшние день и минута места; день ползунка переходит, дуга пересчитывается")
    func nowJumpsAcrossDays() {
        let m = SunARModel(target: target("2026-09-23T06:00:00Z"), source: nil)
        let arcBefore = m.arc
        let now = SunTrack.wallClock(of: Moment(ISO8601DateFormatter().date(from: "2026-10-01T09:00:00Z")!), in: barnaul)
        let got = m.nowTarget(now: Moment(ISO8601DateFormatter().date(from: "2026-10-01T09:00:00Z")!))
        #expect(got.day == now.day && got.minutes == now.minutes)
        m.jump(to: got.day, minutes: got.minutes)
        #expect(m.day == now.day && m.minutes == now.minutes)
        #expect(m.arc != arcBefore)
        #expect(m.arc.count == 145)
    }

    @Test("без датчика камеру водят пальцем, с датчиком — палец не трогает поворот; 360° замыкаются")
    func dragOnlyWithoutSensor() {
        let without = SunARModel(target: target("2026-09-23T06:00:00Z"), source: nil)
        let start = without.look
        without.drag(dx: 100, dy: 50, perPoint: 0.1, from: start)
        #expect(without.look != start)
        without.drag(dx: -4000, dy: 0, perPoint: 0.1, from: start)   // −400°: оборот и ещё 40°
        #expect((0..<360).contains(without.look.azimuth))

        let feed = Feed()
        let with = SunARModel(target: target("2026-09-23T06:00:00Z"), source: feed)
        let s2 = with.look
        with.drag(dx: 100, dy: 50, perPoint: 0.1, from: s2)
        #expect(with.look == s2)
    }

    @Test("курс прыгает при неподвижном телефоне — модель поднимает подсказку; ровный поворот — нет")
    func unsteadyRaisesHint() async {
        let feed = Feed()
        let m = SunARModel(target: target("2026-09-23T06:00:00Z"), source: feed)
        await m.start()
        var t = 0.0
        for i in 0..<20 {
            let az = i % 2 == 0 ? 100.0 : 108
            feed.push?(AttitudeSample(time: t, basis: CameraBasis(azimuth: az, altitude: 10), rotationRate: 1))
            t += 0.05
        }
        #expect(m.unsteady)
        m.stop()

        let calm = Feed()
        let m2 = SunARModel(target: target("2026-09-23T06:00:00Z"), source: calm)
        await m2.start()
        t = 0
        for i in 0..<30 {
            calm.push?(AttitudeSample(time: t, basis: CameraBasis(azimuth: 100 + 40 * t, altitude: 10), rotationRate: 40))
            t += 0.05
            _ = i
        }
        #expect(!m2.unsteady)
        m2.stop()
    }

    @Test("слой открывается местом и моментом и закрывается; других сведений о входе у него нет")
    func openAndClose() {
        let app = AppModel(snapshot: Snapshot(), store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Barnaul")!,
                           locator: IdleLocator(), geocoder: IdleGeocoder(), cityLookup: NoCities(), weatherSource: NoWeather())
        #expect(app.sunAR == nil)
        let t = target("2026-09-23T06:00:00Z")
        app.openSunAR(place: t.place, moment: t.moment)
        #expect(app.sunAR == t)
        app.closeSunAR()
        #expect(app.sunAR == nil)
    }

    private final class IdleLocator: DeviceLocating {
        func currentFix() async -> DeviceFix { .unavailable }
    }
    private struct IdleGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
}
