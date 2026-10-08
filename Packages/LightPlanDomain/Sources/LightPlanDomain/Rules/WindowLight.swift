import Foundation
import LightPlanCore

/// Свет в окнах зала: «прямой», «закатный», «рассеянный» — по солнцу, без
/// погоды (шаг 31в, решение Алексея 08.10: «Свет в окнах зала. Важная задача,
/// нужна реализация сегодня»).
///
/// Правило чистое: место, момент и сторона окон на входе — ответ на выходе, ни
/// экрана, ни сети, ни часов. Парная версия на JS — самодостаточный файл
/// `light_plan:Light_Plan/tools/window_light.js`, его берёт BroniOS. Обе
/// считаются по одной фикстуре, `Fixtures/window_light.json`, которую пишет
/// стенд паритета (`make parity`); пороги заданы в каждой версии отдельно,
/// чтобы сверка поймала расхождение.
///
/// **Не учтено:** погода (облака не смотрим), размер окна, преграды (дом
/// напротив, деревья, козырёк), глубина зала, преломление в атмосфере.
/// Справка для BroniOS: `light_plan:Light_Plan/docs/window_light_reference.md`.
public enum WindowLightKind: String, Hashable, Sendable {
    /// Солнце над горизонтом и светит в окна.
    case direct
    /// То же, но солнце низкое и тёплое — золотой час (`half` говорит какой).
    case golden
    /// Солнце в окна не светит: за стеной, у самого горизонта, под ним.
    case diffuse
    /// В зале нет окон.
    case none
    /// Нет данных (`reason` говорит каких): значение не выдумывается.
    case unknown
}

/// Золотой час, в который попало солнце.
public enum GoldenHalf: String, Hashable, Sendable {
    /// Рассветный: до солнечного полудня.
    case morning
    /// Закатный: после него.
    case evening
}

/// Чего не хватило для ответа.
public enum WindowLightGap: String, Hashable, Sendable {
    case noWindowsFlag = "no_windows_flag"
    case noAzimuth = "no_azimuth"
    case noCoordinates = "no_coordinates"
    case noZone = "no_zone"
    case badZone = "bad_zone"
    case badMoment = "bad_moment"
}

public struct WindowLightAnswer: Hashable, Sendable {
    public let kind: WindowLightKind
    /// Только у `.unknown`.
    public let reason: WindowLightGap?
    /// Только у `.golden`.
    public let half: GoldenHalf?
    /// Градусы над горизонтом (у `.none` и `.unknown` — `nil`).
    public let sunElevation: Double?
    /// Градусы от севера по часовой, `[0, 360)`.
    public let sunAzimuth: Double?
    /// Угол между азимутом солнца и азимутом окон, `0…180`.
    public let offsetFromWindow: Double?
}

public enum WindowLight {

    // MARK: - Пороги — выбор исполнителя 08.10, Алексей может подправить.
    // Меняются здесь и в `window_light.js` одновременно: сверка упадёт, если
    // разойдутся. Обоснование — в `docs/window_light_reference.md`.

    /// Ниже — солнце у самого горизонта: свет идёт сквозь самый толстый слой
    /// воздуха и закрыт любым забором. Окно его «не ловит».
    public static let minElevation: Double = 2
    /// Верх золотого часа — та же шестёрка, что `goldenA`/`goldenB`
    /// солнечной модели. Между `minElevation` и ею — закатный, выше — прямой.
    public static let goldElevation: Double = 6
    /// Солнце «перед окном», если азимут солнца отличается от азимута окон не
    /// более чем на столько. 90° — плоскость стены, 85° — с запасом в 5°.
    public static let maxOffset: Double = 85

    /// Подпись функции — она же честное «чего не знаем».
    public static let note = "по солнцу, без погоды"

    /// Свет в окнах зала в данный момент.
    ///
    /// - Parameters:
    ///   - moment: момент (абсолютный, без пояса); `nil` — «нет данных».
    ///   - latitude, longitude: координаты студии, градусы.
    ///   - zone: имя пояса зала по IANA ("Asia/Tomsk").
    ///   - windowsAzimuth: куда СМОТРЯТ окна, градусы от севера по часовой;
    ///     любое число, приводится к `0…360`.
    ///   - hasWindows: есть ли в зале окна.
    public static func at(
        _ moment: Date?,
        latitude: Double?,
        longitude: Double?,
        zone: String?,
        windowsAzimuth: Double?,
        hasWindows: Bool?
    ) -> WindowLightAnswer {
        /* Окон нет — ответ готов и без координат, момента и пояса */
        if hasWindows == false { return answer(.none) }
        guard hasWindows == true else { return answer(.unknown, reason: .noWindowsFlag) }
        guard let azimuth = windowsAzimuth, azimuth.isFinite else { return answer(.unknown, reason: .noAzimuth) }
        guard let lat = latitude, let lon = longitude, lat.isFinite, lon.isFinite,
              abs(lat) <= 90, abs(lon) <= 180 else { return answer(.unknown, reason: .noCoordinates) }
        guard let zoneName = zone, !zoneName.isEmpty else { return answer(.unknown, reason: .noZone) }
        guard let moment, moment.timeIntervalSince1970.isFinite else { return answer(.unknown, reason: .badMoment) }
        guard let tz = TimeZone(identifier: zoneName) else { return answer(.unknown, reason: .badZone) }

        /* Миллисекунды, как в JS-копии: те же целые на входе обеих версий */
        let ms = (moment.timeIntervalSince1970 * 1000).rounded()
        let offsetMs = Double(tz.secondsFromGMT(for: moment)) * 1000

        /* Сутки и минуты — по часам зала на этот момент */
        let localMs = ms + offsetMs
        let dayNum = (localMs / 86_400_000).rounded(.down)
        let t = (localMs - dayNum * 86_400_000) / 60_000
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = utc.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: dayNum * 86_400))
        let day = CivilDate(year: c.year!, month: c.month!, day: c.day!)

        let sun = SolarDay(date: day, latitude: lat, longitude: lon, utcOffsetHours: offsetMs / 3_600_000)
        let elevation = sun.elevation(at: t)
        let sunAzimuth = sun.azimuth(at: t)

        let wa = (azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        var d = abs(sunAzimuth - wa)
        if d > 180 { d = 360 - d }

        func ans(_ kind: WindowLightKind, _ half: GoldenHalf? = nil) -> WindowLightAnswer {
            WindowLightAnswer(kind: kind, reason: nil, half: half,
                              sunElevation: elevation, sunAzimuth: sunAzimuth, offsetFromWindow: d)
        }
        if elevation < minElevation || d > maxOffset { return ans(.diffuse) }
        if elevation <= goldElevation { return ans(.golden, t >= sun.solarNoon ? .evening : .morning) }
        return ans(.direct)
    }

    private static func answer(_ kind: WindowLightKind, reason: WindowLightGap? = nil) -> WindowLightAnswer {
        WindowLightAnswer(kind: kind, reason: reason, half: nil,
                          sunElevation: nil, sunAzimuth: nil, offsetFromWindow: nil)
    }
}
