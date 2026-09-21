import Foundation

/// Мешает ли луна звёздам в эту ночь: доля тёмной части, когда луна над
/// горизонтом, и наибольшая освещённость диска в это время.
///
/// Порт `moonVsStars` веба. Оценка простая и честная в своих границах: высоту
/// луны отдельно не учитываем — над горизонтом она уже светит. Пороги — по
/// практике съёмки: до четверти диска луна почти не мешает, от четверти до
/// половины мешает заметно, больше половины — Млечного Пути не будет.
///
/// Веб считает чужой день приёмом «сохранить выбранный день → посчитать →
/// вернуть» (`computeSun(keep)`); здесь это второй `SolarDay`, глобалов нет.
public struct MoonVsStars: Sendable, Equatable {

    /// Уровень помехи; сырые значения — те же 0 / 1 / 2, что в вебе.
    public enum Level: Int, Sendable {
        /// Луна не мешает: почти не освещена или почти не над горизонтом.
        case negligible = 0
        /// Мешает заметно.
        case noticeable = 1
        /// Млечного Пути не будет.
        case blocking = 2
    }

    /// Есть ли в эту ночь астрономическая темнота (солнце ниже −18°). Нет —
    /// остальные поля пусты.
    public let dark: Bool
    /// Наибольшая доля освещённого диска, пока луна над горизонтом, `0 ... 1`.
    public let lit: Double
    /// Доля тёмной части ночи с луной над горизонтом, `0 ... 1`.
    public let share: Double
    /// `lit` в целых процентах; `nil`, если темноты нет.
    public let percent: Int?
    /// `nil`, если темноты нет.
    public let level: Level?

    // MARK: - Входы

    public init(date: CivilDate, latitude: Double, longitude: Double, utcOffsetHours: Double) {
        let sun = SolarDay(date: date, latitude: latitude, longitude: longitude, utcOffsetHours: utcOffsetHours)
        // Тёмная часть — от вечернего пересечения −18° до утреннего.
        guard let from = sun.astroB, let end = sun.astroA else {
            self.dark = false; self.lit = 0; self.share = 0; self.percent = nil; self.level = nil
            return
        }
        let to = end + (end < from ? 1440 : 0)

        var up = 0, n = 0
        var litMax = 0.0
        /* Шаг 10 минут — поведение продукта. Счётчик `x += 10`, а не
           `from + i·10`: минуты дробные, и накопление суммы даёт другие биты.
           В вебе ещё стоит `x % 1440 === x ? x : x` — выражение ничего не
           делает, и не переносится. */
        var x = from
        while x <= to {
            let moon = MoonSample(
                date: date, minutes: x,
                latitude: latitude, longitude: longitude, utcOffsetHours: utcOffsetHours
            )
            n += 1
            if moon.altitude > 0 {
                up += 1
                litMax = max(litMax, moon.phase.fraction)
            }
            x += 10
        }
        let share = n > 0 ? Double(up) / Double(n) : 0

        self.dark = true
        self.lit = litMax
        self.share = share
        self.percent = Int(Sky.jsRound(litMax * 100))
        /* Луна под горизонтом всю тёмную часть — мешать нечем, как бы она ни
           была полна: светит она, только когда её видно. */
        if share < 0.1 {
            self.level = .negligible
        } else {
            self.level = litMax > 0.5 ? .blocking : litMax > 0.25 ? .noticeable : .negligible
        }
    }

    public init(date: CivilDate, place: Place) {
        self.init(
            date: date,
            latitude: place.latitude, longitude: place.longitude,
            utcOffsetHours: place.zone.utcOffsetHours(on: date)
        )
    }
}
