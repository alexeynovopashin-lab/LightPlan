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

    // MARK: - Подставные камера и флаг (29.8в.2)

    private final class MemoryFlag: ARCalibrationFlag {
        var seen = false
    }

    /// Камера, которой тест управляет сам: разрешение (и запуск) либо сразу, либо висят, пока тест не «нажмёт» ответ.
    /// Счётчик вызовов растёт в одной секции с сохранением ожидания: тест, дождавшийся счётчика, отвечает уже по
    /// сохранённому (ревью GPT к 9d2cc58, пункт 3). Ответ, пришедший раньше вопроса, запоминается.
    private final class FakeCamera: ARCameraDriving, @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: CheckedContinuation<ARCameraAuthorization, Never>?
        private var early: ARCameraAuthorization?
        private var runWaiting: [CheckedContinuation<ARCameraOutcome, Never>] = []
        private var _authorizeCalls = 0, _runCalls = 0, _stopCalls = 0
        let immediate: ARCameraAuthorization?
        let holdRun: Bool

        init(immediate: ARCameraAuthorization? = .granted, holdRun: Bool = false) {
            self.immediate = immediate
            self.holdRun = holdRun
        }

        var authorizeCalls: Int { lock.withLock { _authorizeCalls } }
        var runCalls: Int { lock.withLock { _runCalls } }
        var stopCalls: Int { lock.withLock { _stopCalls } }

        func authorize() async -> ARCameraAuthorization {
            if let immediate {
                lock.withLock { _authorizeCalls += 1 }
                return immediate
            }
            return await withCheckedContinuation { (c: CheckedContinuation<ARCameraAuthorization, Never>) in
                let ready = lock.withLock { () -> ARCameraAuthorization? in
                    _authorizeCalls += 1
                    if let a = early { early = nil; return a }
                    waiting = c
                    return nil
                }
                if let ready { c.resume(returning: ready) }
            }
        }

        /// Человек нажал в системном окне.
        func answer(_ a: ARCameraAuthorization) {
            let c = lock.withLock { () -> CheckedContinuation<ARCameraAuthorization, Never>? in
                guard let c = waiting else { early = a; return nil }
                waiting = nil
                return c
            }
            c?.resume(returning: a)
        }

        func run() async -> ARCameraOutcome {
            guard holdRun else {
                lock.withLock { _runCalls += 1 }
                return ARCameraOutcome(state: .running, optics: nil)
            }
            return await withCheckedContinuation { (c: CheckedContinuation<ARCameraOutcome, Never>) in
                lock.withLock { _runCalls += 1; runWaiting.append(c) }
            }
        }

        /// Запуск сессии закончился (по порядку вызовов).
        func finishRun(_ index: Int) {
            let c = lock.withLock { () -> CheckedContinuation<ARCameraOutcome, Never>? in
                index < runWaiting.count ? runWaiting[index] : nil
            }
            c?.resume(returning: ARCameraOutcome(state: .running, optics: nil))
        }

        func stop() { lock.withLock { _stopCalls += 1 } }
    }

    private final class MutableClock {
        var moment: Moment
        init(_ iso: String) { moment = Moment(ISO8601DateFormatter().date(from: iso)!) }
        func advance(minutes: Double) { moment = Moment(milliseconds: moment.milliseconds + Int64(minutes * 60_000)) }
    }

    private func model(at iso: String, now: String? = nil, source: (any AttitudeSource)? = nil,
                       camera: FakeCamera = FakeCamera(), flag: MemoryFlag = MemoryFlag(),
                       force: Bool = false, clock: MutableClock? = nil) -> (SunARModel, MutableClock) {
        let c = clock ?? MutableClock(now ?? iso)
        let m = SunARModel(target: target(iso), source: source, camera: camera, clock: { c.moment },
                           calibrationFlag: flag, forceCalibration: force)
        return (m, c)
    }

    // MARK: - Два маркера

    @Test("вход с выбранным на карте моментом: модель встаёт на этот день и минуту, а не на «сейчас»")
    func entryKeepsPickedMoment() {
        // Выбрано 21 июня 14:25 по часам места; «сейчас» — 23 сентября.
        let day = CivilDate(year: 2026, month: 6, day: 21)
        let picked = SunTrack.moment(day: day, minutes: 14 * 60 + 25, in: barnaul)
        let clock = MutableClock("2026-09-23T06:00:00Z")
        let m = SunARModel(target: SunARTarget(place: barnaul, moment: picked), source: nil,
                           camera: FakeCamera(), clock: { clock.moment }, calibrationFlag: MemoryFlag())
        #expect(m.day == day)
        #expect(abs(m.minutes - (14 * 60 + 25)) < 1e-3)
        #expect(!m.pickedIsNow)
    }

    @Test("выбранный момент = сейчас: метки сливаются в одну, подпись одна")
    func mergedWhenPickedIsNow() {
        let (m, _) = model(at: "2026-09-23T06:00:00Z")
        #expect(m.pickedIsNow)
        let scene = SunARScene.make(basis: CameraBasis(azimuth: 190, altitude: 40), optics: .typical,
                                    viewport: ScreenViewport(width: 393, height: 852), arc: m.arc, sun: m.sun,
                                    now: m.sunNow, pickedIsNow: m.pickedIsNow)
        #expect(scene.markerIsNow)
        #expect(scene.marker != nil && scene.nowMarker == nil)
    }

    @Test("другой день, то же время: два маркера, «сейчас» от ползунка не зависит, дуга — выбранного дня")
    func differentDayTwoMarkers() throws {
        let (m, _) = model(at: "2026-12-21T06:00:00Z", now: "2026-09-23T06:00:00Z")
        #expect(!m.pickedIsNow)
        let nowAz = m.sunNow.azimuth
        #expect(m.sun.altitude != m.sunNow.altitude)
        let basis = CameraBasis(azimuth: 190, altitude: 20)
        let scene = SunARScene.make(basis: basis, optics: .typical, viewport: ScreenViewport(width: 393, height: 852),
                                    arc: m.arc, sun: m.sun, now: m.sunNow, pickedIsNow: m.pickedIsNow)
        let a = try #require(scene.marker), b = try #require(scene.nowMarker)
        #expect(hypot(a.x - b.x, a.y - b.y) > 20)
        // Ползунок двигает выбранный момент, «сейчас» стоит.
        m.set(minutes: m.minutes + 120)
        #expect(m.sunNow.azimuth == nowAz)
        // Дуга — декабрьская (день выбранный): в полдень высота ниже, чем в сентябре.
        let noonDec = m.arc.max { $0.altitude < $1.altitude }!.altitude
        let noonSep = SunTrack.arc(day: m.nowTarget().day, in: barnaul).max { $0.altitude < $1.altitude }!.altitude
        #expect(noonDec < noonSep - 10)
    }

    @Test("«Сейчас»: после ползунка выбранный момент возвращается на текущий и метки сливаются")
    func nowButtonMerges() {
        let (m, _) = model(at: "2026-09-23T06:00:00Z")
        m.set(minutes: m.minutes + 180)
        #expect(!m.pickedIsNow)
        m.jumpToNow()
        #expect(m.pickedIsNow)
        #expect(m.day == m.nowTarget().day)
    }

    @Test("«сейчас» едет: через десять минут маркер сдвинулся, выбранный остался на месте")
    func nowMarkerTicks() {
        let (m, clock) = model(at: "2026-09-23T06:00:00Z")
        let before = m.sunNow
        let picked = m.sun
        clock.advance(minutes: 10)
        m.refreshNow()
        #expect(m.sunNow.azimuth != before.azimuth)
        #expect(m.sun == picked)
        #expect(!m.pickedIsNow)
    }

    // MARK: - Плашка «Курс магнитный»

    @Test("магнитный север — плашка есть; север стал истинным — пропала")
    func magneticBanner() async {
        let feed = Feed()
        feed.north = .magneticNorth
        let (m, _) = model(at: "2026-09-23T06:00:00Z", source: feed, flag: { let f = MemoryFlag(); f.seen = true; return f }())
        await m.start()
        #expect(m.magneticOnly)
        feed.north = .trueNorth
        m.refreshNow()
        #expect(!m.magneticOnly)
        m.stop()
    }

    @Test("истинный север с самого начала — плашки нет")
    func noBannerOnTrueNorth() async {
        let feed = Feed()
        let (m, _) = model(at: "2026-09-23T06:00:00Z", source: feed, flag: { let f = MemoryFlag(); f.seen = true; return f }())
        await m.start()
        #expect(!m.magneticOnly)
        m.stop()
    }

    // MARK: - Калибровка

    /// Отсчёты на 30 Гц, курс стоит; возвращает время после последнего.
    private func pump(_ feed: Feed, from t0: Double, seconds: Double, accuracy: MagneticAccuracy?) -> Double {
        var t = t0
        while t < t0 + seconds - 1e-9 {
            feed.push?(AttitudeSample(time: t, basis: CameraBasis(azimuth: 120, altitude: 10), rotationRate: 1,
                                      magneticAccuracy: accuracy))
            t += 1.0 / 30
        }
        return t
    }

    @Test("первый вход: калибровка до камеры; системное окно камеры — только после неё")
    func calibrationBeforeCamera() async {
        let feed = Feed()
        let cam = FakeCamera()
        let flag = MemoryFlag()
        let (m, _) = model(at: "2026-09-23T06:00:00Z", source: feed, camera: cam, flag: flag)
        await m.start()
        #expect(m.calibrating)
        #expect(cam.authorizeCalls == 0, "окно камеры до калибровки не появляется")
        var t = pump(feed, from: 0, seconds: 3, accuracy: .low)
        #expect(m.calibrationPhase == .measuring, "low не годится, как бы долго курс ни стоял")
        #expect(m.calibrationProgress >= 0.5 && m.calibrationProgress < 1)
        t = pump(feed, from: t, seconds: 0.2, accuracy: .medium)
        #expect(m.calibrationPhase == .ready)
        #expect(m.calibrationProgress == 1)
        await m.finishCalibration()
        #expect(!m.calibrating)
        #expect(flag.seen)
        #expect(cam.authorizeCalls == 1 && cam.runCalls == 1)
        #expect(m.camera == .running)
        m.stop()
    }

    @Test("датчика нет: «нет датчика», калибровка не залипает — выход и камера как обычно")
    func calibrationWithoutSensor() async {
        let cam = FakeCamera()
        let flag = MemoryFlag()
        let (m, _) = model(at: "2026-09-23T06:00:00Z", source: nil, camera: cam, flag: flag)
        await m.start()
        #expect(m.calibrating)
        #expect(m.calibrationPhase == .noSensor)
        #expect(m.calibrationProgress == 0)
        await m.finishCalibration()
        #expect(!m.calibrating && flag.seen)
        #expect(cam.runCalls == 1)
        m.stop()
    }

    @Test("пропуск: «Пропустить» выходит из калибровки без «Готово», камера включается, флаг стоит")
    func calibrationSkip() async {
        let feed = Feed()
        let cam = FakeCamera()
        let flag = MemoryFlag()
        let (m, _) = model(at: "2026-09-23T06:00:00Z", source: feed, camera: cam, flag: flag)
        await m.start()
        _ = pump(feed, from: 0, seconds: 0.5, accuracy: .uncalibrated)
        #expect(m.calibrationPhase == .measuring)
        await m.finishCalibration()
        #expect(!m.calibrating && flag.seen && cam.runCalls == 1)
        m.stop()
    }

    @Test("повторный вход: сам калибровка не появляется, камера сразу; кнопка «Калибровка» открывает её снова")
    func calibrationNotShownTwice() async {
        let feed = Feed()
        let flag = MemoryFlag()
        flag.seen = true
        let cam = FakeCamera()
        let (m, _) = model(at: "2026-09-23T06:00:00Z", source: feed, camera: cam, flag: flag)
        await m.start()
        #expect(!m.calibrating)
        #expect(cam.authorizeCalls == 1 && cam.runCalls == 1)
        m.beginCalibration()
        #expect(m.calibrating && m.calibrationPhase == .measuring)
        await m.finishCalibration()
        #expect(cam.authorizeCalls == 1, "камера повторно не поднимается")
        m.stop()
    }

    // MARK: - Камера и закрытый экран (ревью GPT к e7db105, пункт 1)

    @Test("экран закрыли, пока висело системное окно камеры: после «Разрешить» камера не поднимается")
    func cameraNotStartedAfterClose() async {
        let cam = FakeCamera(immediate: nil)
        let flag = MemoryFlag()
        flag.seen = true
        let (m, _) = model(at: "2026-09-23T06:00:00Z", source: Feed(), camera: cam, flag: flag)
        let starting = Task { await m.start() }
        // Ждём, пока модель дойдёт до системного окна.
        for _ in 0..<200 where cam.authorizeCalls == 0 { await Task.yield() }
        #expect(cam.authorizeCalls == 1)
        m.stop()                       // человек закрыл экран, окно ещё на месте
        cam.answer(.granted)           // и только потом нажал «Разрешить»
        await starting.value
        #expect(cam.runCalls == 0, "сессия не должна подниматься за закрытым экраном")
        #expect(m.camera != .running)
    }

    @Test("закрыли и открыли заново, пока старый запуск камеры не вернулся: из старой задачи камера не гасится")
    func staleRunDoesNotStopNewSession() async {
        let cam = FakeCamera(immediate: .granted, holdRun: true)
        let flag = MemoryFlag()
        flag.seen = true
        let (m, _) = model(at: "2026-09-23T06:00:00Z", source: Feed(), camera: cam, flag: flag)
        let first = Task { await m.start() }
        for _ in 0..<400 where cam.runCalls < 1 { await Task.yield() }
        #expect(cam.runCalls == 1)
        m.stop()                      // закрыли: одна остановка от самого `stop`
        let second = Task { await m.start() }
        for _ in 0..<400 where cam.runCalls < 2 { await Task.yield() }
        #expect(cam.runCalls == 2)
        let stopsBefore = cam.stopCalls
        cam.finishRun(0)              // старый запуск вернулся с опозданием
        await first.value
        #expect(cam.stopCalls == stopsBefore, "старая задача не должна гасить новую сессию")
        cam.finishRun(1)
        await second.value
        #expect(m.camera == .running)
        m.stop()
    }

    @Test("экран закрыт, пока показано «Готово»: калибровка не завершается и флаг не ставится")
    func calibrationNotFinishedAfterClose() async {
        let feed = Feed()
        let flag = MemoryFlag()
        let (m, _) = model(at: "2026-09-23T06:00:00Z", source: feed, flag: flag)
        await m.start()
        #expect(m.calibrating)
        m.stop()
        await m.finishCalibration()
        #expect(!flag.seen, "закрытый экран не отмечает калибровку пройденной")
    }

    @Test("экран открыт до конца окна: «Разрешить» поднимает камеру")
    func cameraStartsWhenOpen() async {
        let cam = FakeCamera(immediate: nil)
        let flag = MemoryFlag()
        flag.seen = true
        let (m, _) = model(at: "2026-09-23T06:00:00Z", source: Feed(), camera: cam, flag: flag)
        let starting = Task { await m.start() }
        for _ in 0..<200 where cam.authorizeCalls == 0 { await Task.yield() }
        cam.answer(.granted)
        await starting.value
        #expect(cam.runCalls == 1)
        #expect(m.camera == .running)
        m.stop()
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
