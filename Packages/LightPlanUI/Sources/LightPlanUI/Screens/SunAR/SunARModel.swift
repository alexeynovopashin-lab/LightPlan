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
    let place: Place
    let moment: Moment
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

/// Состояние экрана AR: поворот телефона, камера, выбранный момент и «сейчас», калибровка компаса.
@MainActor @Observable
final class SunARModel {
    let place: Place

    /// День ползунка и минуты по часам места — выбранный момент (то, что выбрали на карте при входе, и дальше
    /// ползунок AR).
    private(set) var day: CivilDate
    var minutes: Double
    /// Дуга выбранного дня — точки через 10 минут от полуночи до полуночи.
    private(set) var arc: [SunSample]

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
    /// Сессия для превью; `nil` у подставной камеры (тесты).
    var cameraSession: AVCaptureSession? { (driver as? ARCameraRig)?.session }
    #endif

    init(target: SunARTarget, source: (any AttitudeSource)?, camera: (any ARCameraDriving)? = nil,
         clock: @escaping @MainActor () -> Moment = { Moment(Date()) },
         calibrationFlag: (any ARCalibrationFlag)? = nil, forceCalibration: Bool = false) {
        place = target.place
        let wall = SunTrack.wallClock(of: target.moment, in: target.place)
        day = wall.day
        minutes = wall.minutes
        arc = SunTrack.arc(day: wall.day, in: target.place)
        self.source = source
        #if os(iOS)
        driver = camera ?? ARCameraRig()
        #else
        driver = camera ?? NoCameraRig()
        #endif
        self.clock = clock
        nowMoment = clock()
        flag = calibrationFlag ?? DeviceCalibrationFlag()
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
            steadiness.add(time: s.time, heading: aim.azimuth, rate: s.rotationRate)
            let now = steadiness.isUnsteady
            if now != unsteady { unsteady = now }
        }
        if calibrating {
            calibration.add(time: s.time, accuracy: s.magneticAccuracy, heading: usable ? aim.azimuth : nil,
                            rate: s.rotationRate)
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
        guard started, epoch == mine else { driver.stop(); return }
        camera = outcome.state
        if let o = outcome.optics { optics = o }
    }

    // MARK: - Калибровка

    var calibrationPhase: CompassCalibration.Phase { calibration.phase }

    /// Шкала `0 … 1` — настоящее качество компаса (`CompassCalibration`), не таймер.
    var calibrationProgress: Double { calibration.progress }

    /// Открыть экран калибровки: первый вход сам, потом — кнопкой «Калибровка».
    func beginCalibration() {
        calibration.reset()
        if !hasSensor { calibration.markNoSensor() }
        calibrating = true
    }

    /// Закрыть калибровку: «Готово», «Пропустить» или «датчика нет». Любой выход помечает экран увиденным —
    /// второй раз сам не появляется. Камера, если ещё не поднималась, поднимается теперь.
    func finishCalibration() async {
        guard calibrating else { return }
        calibrating = false
        flag.seen = true
        await startCamera()
    }

    // MARK: - Взгляд и время

    /// Перенос взгляда пальцем: `dx`, `dy` в точках, `perPoint` — градусов на точку.
    func drag(dx: Double, dy: Double, perPoint: Double, from start: Look) {
        guard !hasSensor else { return }
        var az = start.azimuth - dx * perPoint
        az = (az.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        look = Look(azimuth: az, altitude: min(85, max(-85, start.altitude + dy * perPoint)))
    }

    /// Выбрать минуту дня; день не меняется.
    func set(minutes m: Double) {
        minutes = min(1440, max(0, m))
    }

    /// Кнопка «Сейчас»: день и минута сегодняшние в месте.
    func nowTarget(now: Moment? = nil) -> (day: CivilDate, minutes: Double) {
        SunTrack.wallClock(of: now ?? clock(), in: place)
    }

    func jump(to day: CivilDate, minutes m: Double) {
        if day != self.day {
            self.day = day
            arc = SunTrack.arc(day: day, in: place)
        }
        minutes = min(1440, max(0, m))
    }

    /// «Сейчас» одним шагом: выбранный момент — текущий.
    func jumpToNow() {
        nowMoment = clock()
        let n = nowTarget(now: nowMoment)
        jump(to: n.day, minutes: n.minutes)
    }
}
