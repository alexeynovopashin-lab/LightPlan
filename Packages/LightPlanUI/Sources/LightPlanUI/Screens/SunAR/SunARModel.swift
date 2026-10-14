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

/// Состояние экрана AR: поворот телефона, камера, момент на ползунке, устойчивость курса.
@MainActor @Observable
final class SunARModel {
    let place: Place

    /// День ползунка и минуты по часам места.
    private(set) var day: CivilDate
    var minutes: Double
    /// Дуга выбранного дня — точки через 10 минут от полуночи до полуночи.
    private(set) var arc: [SunSample]

    private(set) var camera: ARCameraState = .starting
    private(set) var optics: CameraOptics = .typical

    /// Поворот телефона с датчика; `nil` — датчика нет или он ещё не прислал отсчёт.
    private(set) var basis: CameraBasis?
    private(set) var north: AttitudeNorth?
    /// Курс прыгает при неподвижном телефоне — показать подсказку «восьмёркой».
    private(set) var unsteady = false
    /// Без датчика (симулятор, Mac) камеру водят пальцем: курс и наклон от жеста.
    struct Look: Equatable { var azimuth: Double; var altitude: Double }
    var look: Look

    private var steadiness = HeadingSteadiness()
    private let source: (any AttitudeSource)?
    private var started = false
    #if os(iOS)
    private let rig = ARCameraRig()
    var cameraSession: AVCaptureSession { rig.session }
    #endif

    init(target: SunARTarget, source: (any AttitudeSource)?) {
        place = target.place
        let wall = SunTrack.wallClock(of: target.moment, in: target.place)
        day = wall.day
        minutes = wall.minutes
        arc = SunTrack.arc(day: wall.day, in: target.place)
        self.source = source
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

    var moment: Moment { SunTrack.moment(day: day, minutes: minutes, in: place) }

    // MARK: - Ход

    func start() async {
        guard !started else { return }
        started = true
        source?.start { [weak self] s in self?.take(s) }
        #if os(iOS)
        let outcome = await rig.start()
        camera = outcome.state
        if let o = outcome.optics { optics = o }
        #else
        camera = .noDevice
        #endif
        north = source?.north
    }

    func stop() {
        source?.stop()
        #if os(iOS)
        rig.stop()
        #endif
        started = false
    }

    private func take(_ s: AttitudeSample) {
        basis = s.basis
        let aim = s.basis.aim
        // У зенита и надира курс не определён: отсчёт в окно не берём.
        if abs(aim.altitude) < 75 {
            steadiness.add(time: s.time, heading: aim.azimuth, rate: s.rotationRate)
            let now = steadiness.isUnsteady
            if now != unsteady { unsteady = now }
        }
    }

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
    func nowTarget(now: Moment = Moment(Date())) -> (day: CivilDate, minutes: Double) {
        SunTrack.wallClock(of: now, in: place)
    }

    func jump(to day: CivilDate, minutes m: Double) {
        if day != self.day {
            self.day = day
            arc = SunTrack.arc(day: day, in: place)
        }
        minutes = min(1440, max(0, m))
    }
}
