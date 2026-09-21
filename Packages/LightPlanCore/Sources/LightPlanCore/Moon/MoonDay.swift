import Foundation

/// Одна дуга луны над горизонтом: восход и заход, целые минуты шкалы. Заход
/// может лежать за 1440 — луна, взошедшая вечером, садится уже на следующие
/// сутки.
public struct MoonArc: Sendable, Equatable {
    public let rise: Minutes
    public let set: Minutes

    public init(rise: Minutes, set: Minutes) {
        self.rise = rise
        self.set = set
    }
}

/// Восход и заход луны выбранного дня в выбранном месте.
///
/// Порт `moonArc` и `moonCross` веба. Луна всходит почти на час позже каждые
/// сутки, поэтому ищем в окне от −720 до +2900 минут шкалы (сутки назад и
/// двое с половиной вперёд) шагом 10 минут; пересечение горизонта уточняется
/// девятью делениями пополам и округляется до минуты. **Шаг, окно и число
/// делений — поведение продукта, не оптимизация**: другое окно находит другие
/// дуги, а точность самой луны низкая (см. `MoonSample`).
///
/// Значение-тип без глобалов. В вебе то же самое лежит в `moonCache` по ключу
/// «дата плюс место»; здесь ключ не нужен — дуги принадлежат экземпляру.
public struct MoonDay: Sendable, Equatable {

    /// Край диска над горизонтом, градусы (`MOON_H0` веба): восходом считается
    /// момент, когда над горизонтом показался верхний край, а не центр.
    static let horizonAltitude: Degrees = 0.125

    /// Все дуги, у которых нашлись и восход, и заход в пределах окна. Дуга без
    /// захода внутри окна найденной не считается (веб: «без захода дуга не
    /// считается найденной»).
    public let arcs: [MoonArc]

    // MARK: - Входы

    public init(date: CivilDate, latitude: Double, longitude: Double, utcOffsetHours: Double) {
        func altitude(_ t: Minutes) -> Degrees {
            MoonSample(
                date: date, minutes: t,
                latitude: latitude, longitude: longitude, utcOffsetHours: utcOffsetHours
            ).altitude - Self.horizonAltitude
        }

        var found: [MoonArc] = []
        var previous = altitude(-720)
        var open: Minutes?
        for step in stride(from: -710, through: 2900, by: 10) {
            let x = Minutes(step)
            let current = altitude(x)
            if previous < 0 && current >= 0 { open = Self.crossing(altitude, x - 10, x) }
            if previous >= 0 && current < 0, let rise = open {
                found.append(MoonArc(rise: rise, set: Self.crossing(altitude, x - 10, x)))
                open = nil
            }
            previous = current
        }
        self.arcs = found
    }

    public init(date: CivilDate, place: Place) {
        self.init(
            date: date,
            latitude: place.latitude, longitude: place.longitude,
            utcOffsetHours: place.zone.utcOffsetHours(on: date)
        )
    }

    // MARK: - Ответ

    /// Дуга, к которой относится момент `t`: та, в которой он лежит, иначе
    /// ближайшая следующая, иначе последняя из найденных. `nil` — луна в окне
    /// не всходит вовсе (за полярным кругом так бывает); веб отвечает этим
    /// полем `none`.
    public func arc(at t: Minutes) -> MoonArc? {
        for arc in arcs where t >= arc.rise && t <= arc.set { return arc }
        for arc in arcs where arc.rise > t { return arc }
        return arcs.last
    }

    // MARK: - Уточнение (`moonCross`)

    /// Девять делений пополам на отрезке `[a, b]`, где высота меняет знак, и
    /// округление до минуты по `Math.round`. Ровно на половине минуты сторону
    /// выбирает последний бит высоты, как у порогов света (§ 5.2 плана), —
    /// поэтому округление веб-овское, а не Swift-овское. Высота `a` хранится, а
    /// не считается заново: функция та же и число то же бит в бит.
    private static func crossing(_ altitude: (Minutes) -> Degrees, _ start: Minutes, _ end: Minutes) -> Minutes {
        var a = start, b = end
        var fa = altitude(a)
        for _ in 0..<9 {
            let m = (a + b) / 2
            let fm = altitude(m)
            if fa * fm <= 0 { b = m } else { a = m; fa = fm }
        }
        return Sky.jsRound((a + b) / 2)
    }
}
