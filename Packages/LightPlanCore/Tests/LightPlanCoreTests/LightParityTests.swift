import Testing
import Foundation
import LightPlanCore

/// Сверка состояния света с вебом (итерация 8). Эталон — `Fixtures/light_state.json`,
/// посчитанный из живой беты стендом `Tools/parity/`. Коды, уровень, тон,
/// зарево, цвет неба, слово о тени и подпись ближайшего события — строго;
/// остаток до события — с допуском времён § 5.2, `1e-6` минуты.
struct LightParityTests {

    /// Отрезки → значение на минуту `t`: последний отрезок, начавшийся не позже `t`.
    private static func run<R>(_ runs: [R], at t: Int, start: (R) -> Int) -> R {
        var lo = 0, hi = runs.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if start(runs[mid]) <= t { lo = mid } else { hi = mid - 1 }
        }
        return runs[lo]
    }

    private static func solarDay(_ d: ParityFixtures.StateDay) -> SolarDay {
        SolarDay(date: CivilDate(iso: d.date), latitude: d.lat, longitude: d.lon, utcOffsetHours: d.tz)
    }

    // MARK: - Каждая минута

    @Test("light_state.json: каждая минута каждого дня — код, уровень, тон, зарево, слово о тени, событие")
    func everyMinute() throws {
        let f = try ParityFixtures.load("light_state.json", as: ParityFixtures.LightStateFile.self)
        var minutes = 0, failures = 0
        var worstRemaining = 0.0
        func fail(_ text: @autoclosure () -> String) {
            failures += 1
            if failures <= 20 { Issue.record(Comment(rawValue: text())) }
        }

        for d in f.days {
            let s = Self.solarDay(d)
            for t in d.t0...d.t1 {
                minutes += 1
                let at = "\(d.date) lat \(d.lat) lon \(d.lon) tz \(d.tz) мин \(t)"
                let got = s.state(at: Double(t))

                let want = Self.run(d.runs, at: t, start: \.t)
                if got.code.rawValue != want.code { fail("\(at): код JS \(want.code), Swift \(got.code.rawValue)") }
                if got.level != want.level { fail("\(at): уровень JS \(String(describing: want.level)), Swift \(String(describing: got.level))") }
                if got.tone.rawValue != want.tone { fail("\(at): тон JS \(want.tone), Swift \(got.tone.rawValue)") }
                if got.glow != want.glow { fail("\(at): зарево JS \(want.glow), Swift \(got.glow)") }
                if got.stars != want.stars { fail("\(at): звёзды JS \(want.stars), Swift \(got.stars)") }

                let word = Self.run(d.shadow, at: t, start: \.t)
                if "shadow.\(s.shadowWord(at: Double(t)).rawValue)" != word.key {
                    fail("\(at): тень JS \(word.key), Swift shadow.\(s.shadowWord(at: Double(t)).rawValue)")
                }

                let next = Self.run(d.next, at: t, start: \.t)
                let n = s.nextLight(at: Double(t))
                if "next.\(n.key.rawValue)" != next.key {
                    fail("\(at): событие JS \(next.key), Swift next.\(n.key.rawValue)")
                }
                switch (next.target, n.minutes) {
                case (nil, nil): break
                case (let target?, let m?):
                    let diff = abs((target - Double(t)) - m)
                    worstRemaining = max(worstRemaining, diff)
                    if !(diff <= 1e-6) { fail("\(at): остаток до события JS \(target - Double(t)), Swift \(m)") }
                default:
                    fail("\(at): остаток до события: у одного из языков его нет")
                }
            }

            // Цвет неба — каждые 10 минут, как записано в фикстуре.
            for c in d.sky {
                let got = LightPalette.skyColor(elevation: s.elevation(at: Double(c[0])))
                if [got.r, got.g, got.b] != Array(c[1...3]) {
                    fail("\(d.date) lat \(d.lat) мин \(c[0]): цвет JS \(Array(c[1...3])), Swift \([got.r, got.g, got.b])")
                }
            }
        }
        print("light: \(minutes) минут, расхождений \(failures), наибольшая разница остатка до события \(worstRemaining)")
        #expect(minutes == f.meta.count)
        #expect(failures == 0, "расхождений: \(failures)")
    }

    // MARK: - Пороги

    /// Допуск 6.05 на границе золотого часа (index.html, 7534) намеренный: без
    /// него на самом стыке показывалось «Вечереет» вместо золотого часа. Тест
    /// обязан его защищать, а не «чинить»: если он покраснел, кто-то сдвинул
    /// порог, и ошибка не в тесте.
    @Test("Допуск 6.05 держит границу золотого часа")
    func goldenHourTolerance() {
        for morning in [true, false] {
            // На самом пороге и ниже — золотой час.
            for e in [6.05, 6.0, 5.99, 6.049999] {
                let s = LightState(elevation: e, morning: morning)
                #expect(s.code == .golden && s.level == 5 && s.tone == .excellent,
                        "\(e)° \(morning ? "утром" : "вечером"): \(s.code), допуск уехал")
            }
            // Чуть выше — уже тёплое утро или вечер, а не золотой час.
            for e in [6.050001, 6.06, 6.1] {
                let s = LightState(elevation: e, morning: morning)
                #expect(s.code == (morning ? .morningWarm : .evening) && s.level == 4,
                        "\(e)° \(morning ? "утром" : "вечером"): \(s.code), порог уехал")
            }
        }
    }

    /// Ровно на 6.05° сторону задаёт строгое «больше»: `e > 6.05` ложно, и
    /// золотой час держится. Числовое значение порога защищено буквально.
    @Test("Порог золотого часа — 6.05, не 6")
    func goldenHourThresholdIsNotSix() {
        #expect(LightState(elevation: 6.05, morning: false).code == .golden)
        #expect(LightState(elevation: 6.05.nextUp, morning: false).code == .evening)
    }

    /// Границы плана: −18/−12/−6/−4/−0.833/0/6/20/40. Что на самой границе и
    /// по ту сторону — записано в вебе строгими и нестрогими неравенствами;
    /// проверяется побитно, а не «примерно».
    @Test("Границы состояний: на пороге и по обе стороны")
    func thresholds() {
        func code(_ e: Double, _ morning: Bool = false) -> LightCode {
            LightState(elevation: e, morning: morning).code
        }
        // 40: строго больше — полдень.
        #expect(code(40) == .day && code(40.nextUp) == .noon)
        // 20: строго больше — день.
        #expect(code(20) == .evening && code(20.nextUp) == .day)
        #expect(code(20, true) == .morningWarm && code(20.nextUp, true) == .morning)
        // 6 — не порог: допуск сдвинул границу на 0.05° вверх.
        #expect(code(6) == .golden && code(6.04) == .golden)
        // 0 — тоже не порог: солнце на горизонте всё ещё золотой час.
        #expect(code(0) == .golden && code(-0.5) == .golden)
        // −0.833: нестрого «больше или равно» — восход/закат по диску.
        #expect(code(-0.833) == .golden && code((-0.833).nextDown) == .sunset)
        #expect(code((-0.833).nextDown, true) == .dawn)
        // −4 (d = 4): строго «меньше 4» — сумерки; на границе — синий час.
        #expect(code(-3.999) == .dusk && code(-4) == .blue)
        #expect(code(-3.999, true) == .dawning)
        // −6: на границе — глубокие сумерки.
        #expect(code(-5.999) == .blue && code(-6) == .deepDusk)
        // −12: на границе — астрономические сумерки.
        #expect(code(-11.999) == .deepDusk && code(-12) == .astroDusk)
        #expect(code(-12, true) == .astroDawn)
        // −18: на границе — ночь.
        #expect(code(-17.999) == .astroDusk && code(-18) == .astroNight)
        // −1.8 — стык заката и сумерек.
        #expect(code(-1.799) == .sunset && code(-1.8) == .dusk)
    }

    @Test("Уровень прибора: пять, четыре, три, два, один; у звёздного неба его нет")
    func metreLevels() {
        func level(_ e: Double) -> Int? { LightState(elevation: e, morning: false).level }
        #expect(level(60) == 2)
        #expect(level(30) == 3)
        #expect(level(10) == 4)
        #expect(level(3) == 5)
        #expect(level(-1) == 5)
        #expect(level(-3) == 4)
        #expect(level(-5) == 5)
        #expect(level(-8) == 1)
        #expect(level(-15) == nil)
        #expect(level(-40) == nil)
        #expect(LightState(elevation: -15, morning: false).stars)
        #expect(!LightState(elevation: -8, morning: false).stars)
    }

    @Test("Слово о тени: границы 0, 10, 25, 45")
    func shadowThresholds() {
        // Слово зависит от высоты, поэтому высота задаётся через сутки, где она известна.
        // Экватор, равноденствие: солнце в зените в полдень, дальше высота падает.
        let s = SolarDay(date: CivilDate(year: 2026, month: 3, day: 20), latitude: 0, longitude: 0, utcOffsetHours: 0)
        func word(elevation e: Double) -> ShadowWord {
            // Обратный ход высоты из времени: утро, левый берег полудня.
            let t = s.solarNoon - (acos(sin(e * .pi / 180) / cos(s.declination)) * 180 / .pi) * 4
            return s.shadowWord(at: t)
        }
        #expect(word(elevation: 60) == .veryShort)
        #expect(word(elevation: 30) == .short)
        #expect(word(elevation: 15) == .long)
        #expect(word(elevation: 5) == .veryLong)
        #expect(s.shadowWord(at: s.mint) == .none)
    }

    // MARK: - Наследство веба

    /// `nextLight` веба читает `null` как 0 — в сравнении и в вычитании. На
    /// практике это «пропустить отсутствующую ветку» (замер: 11 суток сетки).
    /// Закрепляем на двух замеренных сутках, чтобы тихая «починка» не прошла.
    @Test("nextLight: нет золотого или синего часа — ветка пропускается, как в вебе")
    func nextLightSkipsMissingEvents() {
        // 66.6° ю. ш., 20 июня 2026: солнце до 6° не поднимается — золотого часа нет.
        let noGolden = SolarDay(date: CivilDate(year: 2026, month: 6, day: 20), latitude: -66.6, longitude: 37, utcOffsetHours: 2)
        #expect(noGolden.goldenA == nil && noGolden.goldenB == nil && noGolden.polar == .normal)
        #expect(noGolden.nextLight(at: 300).key == .toDawn)
        #expect(noGolden.nextLight(at: 700).key == .toSunset)   // веб: сразу к закату

        // 78° ю. ш., 29 февраля 2028: после заката солнце не уходит ниже −6° — синего часа нет.
        let noBlue = SolarDay(date: CivilDate(year: 2028, month: 2, day: 29), latitude: -78, longitude: 37, utcOffsetHours: 2)
        #expect(noBlue.civilB == nil && noBlue.polar == .normal)
        let n = noBlue.nextLight(at: 1300)
        #expect(n.key == .toDawn)                                // веб: сразу к рассвету
        #expect(n.minutes == (noBlue.rise! + 1440) - 1300)
    }

    @Test("Полярные сутки и ночь: события нет")
    func polarNextLight() {
        let day = SolarDay(date: CivilDate(year: 2026, month: 6, day: 21), latitude: 90, longitude: 0, utcOffsetHours: 0)
        let night = SolarDay(date: CivilDate(year: 2026, month: 12, day: 21), latitude: 90, longitude: 0, utcOffsetHours: 0)
        #expect(day.nextLight(at: 100) == NextLight(key: .polarDay, minutes: nil))
        #expect(night.nextLight(at: 100) == NextLight(key: .polarNight, minutes: nil))
    }

    // MARK: - Состав

    @Test("Кодов пятнадцать, и все встречаются в сетке")
    func allFifteenCodes() throws {
        #expect(LightCode.allCases.count == 15)
        let f = try ParityFixtures.load("light_state.json", as: ParityFixtures.LightStateFile.self)
        let seen = Set(f.days.flatMap { $0.runs.map(\.code) })
        #expect(seen == Set(LightCode.allCases.map(\.rawValue)))
    }

    // MARK: - Метки и пробы

    /// Пробы в сотой градуса от порога: сторона определена, строгое равенство
    /// кодов проверяемо (см. замер 20 сентября 2026 в § 5.2).
    @Test("Пробы у порогов: код, уровень, тон, зарево строго")
    func guardsMatch() throws {
        let f = try ParityFixtures.load("light_state.json", as: ParityFixtures.LightStateFile.self)
        var failures = 0
        for g in f.guards {
            let s = SolarDay(date: CivilDate(iso: g.date), latitude: g.lat, longitude: g.lon, utcOffsetHours: g.tz)
            let got = s.state(at: g.t)
            if got.code.rawValue != g.k || got.level != g.level || got.tone.rawValue != g.tone || got.glow != g.glow {
                failures += 1
                if failures <= 20 { Issue.record("\(g.date) lat \(g.lat) h \(g.h) side \(g.side): JS \(g.k), Swift \(got.code.rawValue)") }
            }
        }
        #expect(!f.guards.isEmpty)
        #expect(failures == 0, "расхождений: \(failures)")
    }

    /// Метки ровно на пороге. Здесь сторону выбирает последний бит, поэтому
    /// строгого равенства нет и быть не может; это показание, не проверка.
    /// Считаем, сколько меток разошлись, и требуем, чтобы разошлись только те,
    /// что лежат на порогах со строгим неравенством.
    @Test("Метки на самом пороге: расхождения только на строгих порогах")
    func marksOnlyDivergeAtStrictThresholds() throws {
        let f = try ParityFixtures.load("light_state.json", as: ParityFixtures.LightStateFile.self)
        var diverged: [Double: Int] = [:]
        for m in f.marks {
            let s = SolarDay(date: CivilDate(iso: m.date), latitude: m.lat, longitude: m.lon, utcOffsetHours: m.tz)
            if s.state(at: m.t).code.rawValue != m.k { diverged[m.h, default: 0] += 1 }
        }
        print("light: метки на пороге разошлись по порогам: \(diverged.sorted { $0.key < $1.key })")
        // Разойтись могут только метки на настоящих порогах; 0 и 6 порогами не являются и расходиться не вправе.
        #expect(diverged.keys.allSatisfy { $0 == 6.05 || $0 == 40 || $0 == 20 || $0 == -0.833 || $0 == -4 || $0 == -6 || $0 == -12 || $0 == -18 })
    }

    // MARK: - Палитра

    @Test("lerp: зажим 0…1, округление половины вверх")
    func lerpRules() {
        let a = SkyColor(0, 0, 0), b = SkyColor(255, 255, 255)
        #expect(LightPalette.lerp(a, b, -1) == a)
        #expect(LightPalette.lerp(a, b, 2) == b)
        #expect(LightPalette.lerp(a, SkyColor(1, 3, 5), 0.5) == SkyColor(1, 2, 3))   // 0.5→1, 1.5→2, 2.5→3
        #expect(LightPalette.lerp(b, a, 0.5) == SkyColor(128, 128, 128))
    }

    @Test("Цвета лестницы на опорных высотах")
    func skyAnchors() {
        #expect(LightPalette.skyColor(elevation: 60) == LightPalette.silver)
        #expect(LightPalette.skyColor(elevation: 10) == LightPalette.amber)
        #expect(LightPalette.skyColor(elevation: 0) == LightPalette.gold)
        #expect(LightPalette.skyColor(elevation: -1.8) == LightPalette.scarlet)
        #expect(LightPalette.skyColor(elevation: -4) == LightPalette.pink)
        #expect(LightPalette.skyColor(elevation: -6) == LightPalette.blue)
        #expect(LightPalette.skyColor(elevation: -12) == LightPalette.deep)
        #expect(LightPalette.skyColor(elevation: -18) == LightPalette.night)
        #expect(LightPalette.skyColor(elevation: -80) == LightPalette.night)
    }
}
