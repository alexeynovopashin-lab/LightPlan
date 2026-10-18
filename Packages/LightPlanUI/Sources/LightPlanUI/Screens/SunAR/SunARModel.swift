import SwiftUI
import LightPlanCore
import LightPlanData
#if os(iOS)
import AVFoundation
#endif

/// Вход в экран AR: место и момент. Больше экран ничего не знает — откуда его открыли, ему безразлично
/// (слово Алексея 14.10: «кнопка AR на экране карты, но с возможностью изменения решения»). Точку входа можно
/// перенести в «Свет» или в карточку съёмки, не трогая сам экран: любое из этих мест умеет собрать `Place` и момент.
///
/// Нужна именно `Place`, а не одна координата: подписи часов на дуге — по часам места, а пояс у координаты
/// не вычисляется без места (Томск и Москва в одном и том же моменте показывают часы с разницей в четыре часа).
struct SunARTarget: Equatable {
    /// Для какого места считается солнце: телефон или, если он положения не дал, выбранное в приложении.
    var choice: SunARPlaceChoice
    let moment: Moment

    var place: Place { choice.place }

    init(choice: SunARPlaceChoice, moment: Moment) {
        self.choice = choice
        self.moment = moment
    }

    /// Место задано прямо (тесты, отладка): считается как «выбранное».
    init(place: Place, moment: Moment) {
        self.init(choice: .chosen(place), moment: moment)
    }
}

/// Был ли экран калибровки показан на этом устройстве. Флаг устройства, как «Щелчки слайдера»: в снимок съёмок и
/// в облако не уходит.
@MainActor
protocol ARCalibrationFlag: AnyObject {
    var seen: Bool { get set }
}

@MainActor
final class DeviceCalibrationFlag: ARCalibrationFlag {
    static let key = "lightplan.native.sunar.calibrationSeen"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var seen: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// Включатели «Луна» и «Млечный Путь» на экране AR (шаг 29.8в.4). Флаги устройства, как калибровка: в снимок
/// съёмок и в облако не уходят, помнятся между входами. По умолчанию выключены.
@MainActor
protocol ARBodiesSettings: AnyObject {
    var moon: Bool { get set }
    var milkyWay: Bool { get set }
}

@MainActor
final class DeviceBodiesSettings: ARBodiesSettings {
    static let moonKey = "lightplan.native.sunar.moon"
    static let milkyWayKey = "lightplan.native.sunar.milkyWay"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var moon: Bool {
        get { defaults.bool(forKey: Self.moonKey) }
        set { defaults.set(newValue, forKey: Self.moonKey) }
    }
    var milkyWay: Bool {
        get { defaults.bool(forKey: Self.milkyWayKey) }
        set { defaults.set(newValue, forKey: Self.milkyWayKey) }
    }
}

/// Состояние экрана AR: поворот телефона, камера, выбранный момент и «сейчас», калибровка компаса.
@MainActor @Observable
final class SunARModel {
    /// Откуда место: телефон или выбранное в приложении. Меняется, когда телефон ответил позже, чем открылся экран.
    private(set) var choice: SunARPlaceChoice
    var place: Place { choice.place }

    /// Таймбар экрана «Свет» — тот же компонент (шаг 29.8в.3), но свой, не тот, что у «Света»: ползунок AR
    /// не двигает время приложения. День и минута выбранного момента живут в его машине времени.
    let timebar: TimebarState

    /// День ползунка и минуты по часам места — выбранный момент (то, что выбрали на карте при входе, и дальше
    /// ползунок AR).
    var day: CivilDate { timebar.machine.selectedDate }
    var minutes: Double { timebar.machine.viewMinute }

    /// Дуга выбранного дня — точки через 10 минут от полуночи до полуночи. Считается по требованию и держится,
    /// пока не сменились день и место (ползунок перелистывает сутки сам, передачей разряда).
    var arc: [SunSample] {
        let d = day, p = place
        if let c = arcCache, c.day == d, c.place == p { return c.arc }
        let a = SunTrack.arc(day: d, in: p)
        arcCache = (d, p, a)
        return a
    }
    @ObservationIgnored private var arcCache: (day: CivilDate, place: Place, arc: [SunSample])?

    /// Сутки выбранного дня: восход, закат, полдень — для строки «до заката» и меток на горизонте.
    var solar: SolarDay { timebar.solarDay }

    /// Высота солнца в прошлый отсчёт ползунка: по ней видно, что ручка пересекла порог света.
    @ObservationIgnored private var lastAltitude: Double?
    @ObservationIgnored private var lastDay: CivilDate?
    /// Отдача на пороге — тот же щелчок, что у таймбара на часе (второго не заводим).
    @ObservationIgnored var thresholdHaptic: (@MainActor () -> Void)?

    /// Часы «сейчас» для маркера «сейчас»; обновляются `refreshNow`.
    private(set) var nowMoment: Moment

    private(set) var camera: ARCameraState = .starting
    private(set) var optics: CameraOptics = .typical

    /// Поворот телефона с датчика; `nil` — датчика нет или он ещё не прислал отсчёт.
    private(set) var basis: CameraBasis?
    /// От какого севера идут отсчёты. `magneticNorth` — плашка «Курс магнитный…».
    private(set) var north: AttitudeNorth?
    /// Курс прыгает при неподвижном телефоне — показать подсказку «восьмёркой».
    private(set) var unsteady = false
    /// Без датчика (симулятор, Mac) камеру водят пальцем: курс и наклон от жеста.
    struct Look: Equatable { var azimuth: Double; var altitude: Double }
    var look: Look

    /// Экран калибровки поверх AR открыт.
    private(set) var calibrating = false
    private(set) var calibration = CompassCalibration()

    private var steadiness = HeadingSteadiness()
    private let source: (any AttitudeSource)?
    private let driver: any ARCameraDriving
    private let clock: @MainActor () -> Moment
    private let flag: any ARCalibrationFlag
    private let forceCalibration: Bool
    private var started = false
    /// Номер захода: `stop` его меняет, и всё, что ждало системное окно камеры, понимает, что экран уже закрыт.
    private var epoch = 0
    private var cameraRequested = false

    #if os(iOS)
    /// Откуда фон берёт кадр: сессия с превью и слоем дисков, подставная камера (отладка) — или `nil`
    /// у подставной камеры тестов.
    var cameraFeed: ARFrameFeed? { (driver as? ARFrameFeeding)?.feed }
    #endif

    // MARK: - Луна и Млечный Путь (29.8в.4)

    private let bodies: any ARBodiesSettings
    private(set) var moonOn: Bool
    private(set) var milkyWayOn: Bool

    func setMoon(_ on: Bool) {
        moonOn = on
        bodies.moon = on
    }

    func setMilkyWay(_ on: Bool) {
        milkyWayOn = on
        bodies.milkyWay = on
    }

    /// Луна в выбранный момент и «сейчас».
    var moonPicked: MoonARSample { MoonTrack.sample(day: day, minutes: minutes, in: place) }
    var moonNow: MoonARSample { MoonTrack.sample(at: nowMoment, in: place) }

    /// Дуга луны выбранного дня: держится, пока не сменились день и место.
    var moonArc: [MoonARSample] {
        let d = day, p = place
        if let c = moonArcCache, c.day == d, c.place == p { return c.arc }
        let a = MoonTrack.arc(day: d, in: p)
        moonArcCache = (d, p, a)
        return a
    }
    @ObservationIgnored private var moonArcCache: (day: CivilDate, place: Place, arc: [MoonARSample])?

    /// Полоса Млечного Пути на выбранный момент: держится, пока не сдвинулась минута.
    private var band: [(left: HorizontalPoint, right: HorizontalPoint)] {
        let d = day, p = place, m = minutes
        if let c = bandCache, c.day == d, c.place == p, c.minutes == m { return c.band }
        let b = MilkyWayAR.band(day: d, minutes: m, in: p)
        bandCache = (d, p, m, b)
        return b
    }
    @ObservationIgnored private var bandCache: (day: CivilDate, place: Place, minutes: Minutes,
                                                 band: [(left: HorizontalPoint, right: HorizontalPoint)])?

    /// Луна и Млечный Путь на экране камеры — только то, что включено. Расчёт — ядра (`MoonSample`, `MoonPhase`,
    /// `MilkyWay`), здесь он только собирается в сцену.
    func nightScene(basis: CameraBasis, optics: CameraOptics, viewport: ScreenViewport) -> NightSkyARScene {
        let s = sun
        let sunPicked = HorizontalPoint(altitude: s.apparentAltitude, azimuth: s.azimuth)
        let n = sunNow
        let moon: NightSkyARScene.MoonInput? = moonOn
            ? .init(arc: moonArc, picked: moonPicked, now: pickedIsNow ? nil : moonNow, sunAtPicked: sunPicked,
                    sunAtNow: HorizontalPoint(altitude: n.apparentAltitude, azimuth: n.azimuth))
            : nil
        let mw: NightSkyARScene.MilkyWayInput? = milkyWayOn
            ? .init(band: band, core: MilkyWayAR.core(day: day, minutes: minutes, in: place), sunAltitude: s.altitude)
            : nil
        return NightSkyARScene.make(basis: basis, optics: optics, viewport: viewport, moon: moon, milkyWay: mw)
    }

    init(target: SunARTarget, source: (any AttitudeSource)?, camera: (any ARCameraDriving)? = nil,
         clock: @escaping @MainActor () -> Moment = { Moment(Date()) },
         calibrationFlag: (any ARCalibrationFlag)? = nil, forceCalibration: Bool = false,
         bodies: (any ARBodiesSettings)? = nil,
         language: String = "ru", clockPreference: ClockPreference = .auto) {
        choice = target.choice
        let wall = SunTrack.wallClock(of: target.moment, in: target.place)
        // Часы таймбара — часы модели: «сейчас» и кнопка «↺ сейчас» тикают от одного источника (в тестах подставного).
        timebar = TimebarState(place: target.place, date: wall.day, weather: nil, language: language,
                               clockPreference: clockPreference,
                               now: { MainActor.assumeIsolated { clock().date } })
        timebar.show(day: wall.day, minute: wall.minutes)
        self.source = source
        #if os(iOS)
        #if DEBUG
        // `-LPSunARFakeCamera 1`: подставные кадры для симулятора (проверка слоя дисков и замеры).
        let synthetic: (any ARCameraDriving)? = UserDefaults.standard.bool(forKey: "LPSunARFakeCamera") ? SyntheticCameraRig() : nil
        driver = camera ?? synthetic ?? ARCameraRig()
        #else
        driver = camera ?? ARCameraRig()
        #endif
        #else
        driver = camera ?? NoCameraRig()
        #endif
        self.clock = clock
        nowMoment = clock()
        flag = calibrationFlag ?? DeviceCalibrationFlag()
        let b = bodies ?? DeviceBodiesSettings()
        self.bodies = b
        moonOn = b.moon
        milkyWayOn = b.milkyWay
        self.forceCalibration = forceCalibration
        // Взгляд без датчика — на солнце в полдень, чуть над горизонтом: дуга видна с первой секунды.
        let noon = SolarDay(date: wall.day, place: target.place)
        look = Look(azimuth: noon.azimuth(at: noon.solarNoon), altitude: 20)
    }

    // MARK: - Вычисляемое

    /// Датчик есть: поворот идёт от телефона.
    var hasSensor: Bool { source?.isAvailable ?? false }

    /// Куда смотрит кадр сейчас.
    var aim: CameraBasis { basis ?? CameraBasis(azimuth: look.azimuth, altitude: look.altitude) }

    /// Солнце в выбранную минуту выбранного дня.
    var sun: SunSample { SunTrack.sample(day: day, minutes: minutes, in: place) }

    /// Строка под временем: «до заката …», «после заката …», «до рассвета …».
    var eventNote: SunTrack.EventNote { SunTrack.note(at: minutes, solar: solar) }

    /// Солнце сию минуту.
    var sunNow: SunSample { SunTrack.sample(at: nowMoment, in: place) }

    var moment: Moment { SunTrack.moment(day: day, minutes: minutes, in: place) }

    /// Выбранный момент совпадает с «сейчас» (в пределах минуты): метки сливаются в одну.
    var pickedIsNow: Bool {
        let n = SunTrack.wallClock(of: nowMoment, in: place)
        return n.day == day && abs(n.minutes - minutes) < 1
    }

    /// Истинный север недоступен: курс магнитный, дуга может уходить на склонение (~10° в Москве).
    var magneticOnly: Bool { north == .magneticNorth }

    // MARK: - Ход

    func start() async {
        guard !started else { return }
        started = true
        source?.start { [weak self] s in self?.take(s) }
        north = source?.north
        if forceCalibration || !flag.seen {
            // Первое включение на устройстве: калибровка, и только потом системное окно камеры.
            beginCalibration()
            return
        }
        await startCamera()
    }

    func stop() {
        source?.stop()
        driver.stop()
        started = false
        cameraRequested = false
        epoch += 1
    }

    /// Раз в несколько секунд: «сейчас» едет, север мог стать истинным.
    func refreshNow() {
        nowMoment = clock()
        source?.recheckNorth()
        let n = source?.north
        if n != north { north = n }
    }

    private func take(_ s: AttitudeSample) {
        basis = s.basis
        let aim = s.basis.aim
        // У зенита и надира курс не определён: отсчёт в окно устойчивости не берём.
        let usable = abs(aim.altitude) < 75
        if usable {
            steadiness.add(time: s.time, heading: aim.azimuth, rate: s.headingRate)
            let now = steadiness.isUnsteady
            if now != unsteady { unsteady = now }
        }
        if calibrating {
            // Шкала растёт от движения (гироскоп и положение), точность — то, что отвечает система.
            calibration.add(s.calibrationReading)
        }
        // Север мог определиться по первому отсчёту (источник выставляет его в `start`).
        if north == nil, let n = source?.north { north = n }
    }

    // MARK: - Камера

    /// Системное окно спрашивается здесь. Между вопросом и включением проверяется, что экран не закрыли:
    /// иначе камера поднялась бы за закрытым экраном и горела зелёным индикатором.
    private func startCamera() async {
        guard started, !cameraRequested else { return }
        cameraRequested = true
        let mine = epoch
        let auth = await driver.authorize()
        guard started, epoch == mine else { return }
        switch auth {
        case .noDevice: camera = .noDevice; return
        case .denied: camera = .denied; return
        case .restricted: camera = .restricted; return
        case .granted: break
        }
        let outcome = await driver.run()
        // Экран закрыли, пока камера поднималась: `stop()` уже поставил остановку в очередь камеры после запуска.
        // Останавливать отсюда ещё раз нельзя — при повторном открытии это выключило бы уже новую сессию.
        guard started, epoch == mine else { return }
        camera = outcome.state
        if let o = outcome.optics { optics = o }
    }

    // MARK: - Калибровка

    var calibrationPhase: CompassCalibration.Phase { calibration.phase }

    /// Шкала `0 … 1` — охват движения по гироскопу (`CompassCalibration`), не таймер и не точность.
    var calibrationProgress: Double { calibration.progress }

    /// Открыть экран калибровки: первый вход сам, потом — кнопкой «Калибровка».
    func beginCalibration() {
        calibration.reset()
        if !hasSensor { calibration.markNoSensor() }
        calibrating = true
    }

    /// Закрыть калибровку: «Готово» (только когда `canFinish`) или «Пропустить»; сама она не закрывается — ни по
    /// таймеру, ни по «Готово» (шаг 29.8в.8). Любой выход помечает экран увиденным — второй раз сам не появляется. Камера, если ещё не поднималась, поднимается теперь.
    func finishCalibration() async {
        // После `stop()` экран закрыт: «Готово», показанное на закрывающемся экране, флаг не ставит.
        guard calibrating, started else { return }
        calibrating = false
        flag.seen = true
        await startCamera()
    }

    /// «Готово»: только когда охват полный и точность не хуже порога.
    func doneCalibration() async {
        guard calibration.canFinish else { return }
        await finishCalibration()
    }

    /// «Ещё раз»: шкала и точность при входе — заново.
    func retryCalibration() {
        guard calibrating else { return }
        calibration.reset()
        if !hasSensor { calibration.markNoSensor() }
    }

    // MARK: - Взгляд и время

    /// Перенос взгляда пальцем: `dx`, `dy` в точках, `perPoint` — градусов на точку.
    func drag(dx: Double, dy: Double, perPoint: Double, from start: Look) {
        guard !hasSensor else { return }
        var az = start.azimuth - dx * perPoint
        az = (az.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        look = Look(azimuth: az, altitude: min(85, max(-85, start.altitude + dy * perPoint)))
    }

    /// Телефон ответил позже, чем открылся экран (или выбранное место заменено телефонным): считаем для нового
    /// места. Момент остаётся тем же — меняются часы места и пояс, а не мгновение.
    func apply(choice new: SunARPlaceChoice) {
        guard new != choice else { return }
        let instant = moment
        let old = place
        choice = new
        guard new.place != old else { return }
        timebar.setPlace(new.place)
        let wall = SunTrack.wallClock(of: instant, in: new.place)
        timebar.show(day: wall.day, minute: wall.minutes)
        lastAltitude = nil
    }

    /// Выбрать минуту дня; день не меняется.
    func set(minutes m: Double) {
        timebar.dragDome(to: m)
    }

    /// Ручка таймбара сдвинулась: если между прошлым и нынешним положением лежит порог света (золотой час,
    /// закат, синий час) — одна отдача. День сменился передачей разряда — у неё своя отдача, порог не считаем.
    func minuteMoved() {
        let altitude = sun.altitude
        defer { lastAltitude = altitude; lastDay = day }
        guard let was = lastAltitude, lastDay == day else { return }
        if SunTrack.thresholdsCrossed(from: was, to: altitude) > 0 {
            if let thresholdHaptic { thresholdHaptic() } else { timebar.haptics.detent() }
        }
    }

    /// Кнопка «Сейчас»: день и минута сегодняшние в месте.
    func nowTarget(now: Moment? = nil) -> (day: CivilDate, minutes: Double) {
        SunTrack.wallClock(of: now ?? clock(), in: place)
    }

    func jump(to day: CivilDate, minutes m: Double) {
        timebar.show(day: day, minute: m)
    }

    /// «Сейчас» одним шагом: выбранный момент — текущий.
    func jumpToNow() {
        nowMoment = clock()
        let n = nowTarget(now: nowMoment)
        jump(to: n.day, minutes: n.minutes)
    }

    /// Выбранный день и минута в таймбаре — отсюда «сейчас» плавно едет кадр за кадром (экран).
    var wallNow: (day: CivilDate, minutes: Double) { nowTarget(now: nowMoment) }
}
