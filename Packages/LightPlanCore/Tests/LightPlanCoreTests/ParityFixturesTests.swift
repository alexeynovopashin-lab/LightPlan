import Testing
import Foundation

/// Заглушка стенда паритета: движка ещё нет, поэтому сверять числа не с чем.
/// Эти тесты доказывают другое — фикстуры на месте, читаются Swift и внутренне
/// непротиворечивы. Когда появится `SolarDay` (итерация 7), сюда придёт сверка,
/// а загрузчик останется тем же.
struct ParityFixturesTests {

    @Test("Все шесть фикстур читаются и посчитаны одной вырезкой из беты")
    func allFixturesLoad() throws {
        let solar = try ParityFixtures.load("solar_day.json", as: ParityFixtures.SolarDayFile.self)
        let sample = try ParityFixtures.load("solar_sample.json", as: ParityFixtures.SolarSampleFile.self)
        let light = try ParityFixtures.load("light_state.json", as: ParityFixtures.LightStateFile.self)
        let score = try ParityFixtures.load("sunset_score.json", as: ParityFixtures.SunsetScoreFile.self)
        let moon = try ParityFixtures.load("moon.json", as: ParityFixtures.MoonFile.self)
        let mw = try ParityFixtures.load("milkyway.json", as: ParityFixtures.MilkyWayFile.self)

        let cuts = Set([solar.meta.cut, sample.meta.cut, light.meta.cut,
                        score.meta.cut, moon.meta.cut, mw.meta.cut])
        #expect(cuts.count == 1, "фикстуры посчитаны разными состояниями беты: \(cuts). Собрать заново: make parity")

        #expect(solar.days.count == solar.meta.count)
        #expect(sample.series.reduce(0) { $0 + $1.t.count } == sample.meta.count)
        #expect(light.days.reduce(0) { $0 + ($1.t1 - $1.t0 + 1) } == light.meta.count)
        #expect(score.scores.count + score.air.count == score.meta.count)
        #expect(moon.series.reduce(0) { $0 + $1.t.count } == moon.meta.count)
        #expect(mw.band.count + mw.coreAltAz.count == mw.meta.count)
    }

    @Test("Ряды солнца: время, высота, азимут и тень одной длины")
    func solarSeriesAreAligned() throws {
        let f = try ParityFixtures.load("solar_sample.json", as: ParityFixtures.SolarSampleFile.self)
        for s in f.series {
            #expect(s.elev.count == s.t.count && s.az.count == s.t.count && s.shadow.count == s.t.count,
                    "ряд \(s.date) на широте \(s.lat) разной длины")
            #expect(s.az.allSatisfy { $0 >= 0 && $0 < 360 }, "азимут вне круга: \(s.date)")
        }
    }

    @Test("Полярные сутки: ни восхода, ни заката — и наоборот")
    func polarDaysHaveNoEvents() throws {
        let f = try ParityFixtures.load("solar_day.json", as: ParityFixtures.SolarDayFile.self)
        var polar = 0
        for d in f.days where d.polar != 0 {
            polar += 1
            #expect(d.rise == nil && d.set == nil, "\(d.date) на \(d.lat)°: полярность \(d.polar), а событие есть")
            /* Дуга купола в полярные сутки — целые сутки, иначе светило
               превратилось бы в NaN и исчезло с экрана. */
            #expect(d.arcA == d.mint && d.arcB == d.maxt)
        }
        #expect(polar > 0, "в сетке не оказалось ни одних полярных суток — проверять стало нечего")
    }

    @Test("Отрезки состояний идут подряд и начинаются с начала шкалы")
    func stateRunsAreOrdered() throws {
        let f = try ParityFixtures.load("light_state.json", as: ParityFixtures.LightStateFile.self)
        for d in f.days {
            #expect(d.runs.first?.t == d.t0, "\(d.date) на \(d.lat)°: первый отрезок не с t0")
            var prev = Int.min
            for r in d.runs {
                #expect(r.t > prev, "\(d.date) на \(d.lat)°: отрезки не по возрастанию")
                #expect(r.t >= d.t0 && r.t <= d.t1)
                prev = r.t
            }
        }
    }

    /// Плановые «13 состояний света» — число из первой редакции. Замер стендом
    /// 20 сентября 2026: кодов пятнадцать, и столько же ключей в словаре.
    /// Пять веток `stateAt` дают по два кода — утренний и вечерний.
    @Test("Состояний света пятнадцать")
    func fifteenLightStates() throws {
        let f = try ParityFixtures.load("light_state.json", as: ParityFixtures.LightStateFile.self)
        let codes = Set(f.days.flatMap { $0.runs.map(\.code) })
        #expect(codes.count == 15, "кодов \(codes.count): \(codes.sorted())")
        let known: Set<String> = ["noon", "morning", "day", "morningWarm", "evening", "golden",
                                  "dawn", "sunset", "dawning", "dusk", "blue", "deepDusk",
                                  "astroDawn", "astroDusk", "astroNight"]
        #expect(codes == known)
    }

    /// Допуск 6.05 на границе золотого часа (index.html, 7534) — намеренный:
    /// без него на самом стыке показывалось «Вечереет» вместо золотого часа.
    /// Тест обязан его защищать, а не «чинить».
    ///
    /// Проверяется по обе стороны порога, а не на самом пороге: замер стендом
    /// показал, что ровно на 6.05° сторону выбирает последний бит высоты
    /// (обратный ход сходится до 4e-14°, и этого хватает). Сотая градуса от
    /// порога — расстояние, на котором ответ не зависит ни от языка, ни от
    /// библиотеки синусов.
    @Test("Допуск 6.05 держит границу золотого часа")
    func goldenHourToleranceIsProtected() throws {
        let f = try ParityFixtures.load("light_state.json", as: ParityFixtures.LightStateFile.self)
        let below = f.guards.filter { $0.h == 6.05 && $0.side < 0 }
        let above = f.guards.filter { $0.h == 6.05 && $0.side > 0 }
        #expect(!below.isEmpty && !above.isEmpty, "в фикстуре нет проб вокруг 6.05°")
        #expect(below.allSatisfy { $0.k == "golden" && $0.level == 5 && $0.tone == "excellent" },
                "ниже 6.05° уже не золотой час — допуск уехал")
        #expect(above.allSatisfy { $0.k == "morningWarm" || $0.k == "evening" },
                "выше 6.05° всё ещё золотой час — порог уехал")
        #expect(above.allSatisfy { $0.level == 4 })

        /* Ровно 6° порогом не является: допуск сдвинул границу на 0.05° вверх,
           и на шести градусах всё ещё золотой час — во всех 346 метках. */
        let atSix = f.marks.filter { $0.h == 6 }
        #expect(!atSix.isEmpty && atSix.allSatisfy { $0.k == "golden" })
    }

    @Test("Метки границ: обратный ход высоты сходится до 1e-9°")
    func boundaryRoundTripIsTight() throws {
        let f = try ParityFixtures.load("light_state.json", as: ParityFixtures.LightStateFile.self)
        #expect(!f.marks.isEmpty)
        for m in f.marks {
            #expect(abs(m.elev - m.h) < 1e-9,
                    "\(m.date) на \(m.lat)°: высота вернулась как \(m.elev) вместо \(m.h)")
        }
        for g in f.guards {
            #expect(abs(g.elev - (g.h + Double(g.side) * 0.01)) < 1e-9)
        }
    }

    @Test("Сетка закатного балла полная, баллы в пределах 0…100")
    func sunsetScoreGridIsComplete() throws {
        let f = try ParityFixtures.load("sunset_score.json", as: ParityFixtures.SunsetScoreFile.self)
        #expect(f.order == "low,mid,high,hum")
        let n = f.axis.count
        #expect(f.scores.count == n * n * n * n, "сетка неполная: \(f.scores.count) вместо \(n * n * n * n)")
        #expect(f.scores.allSatisfy { $0 >= 0 && $0 <= 100 })
        #expect(f.air.allSatisfy { $0.score >= 0 && $0.score <= 100 })
    }

    /// Контрольные точки из комментария к слою (index.html, 6930): перевод
    /// галактических координат в экваториальные проверяется ими же в вебе.
    @Test("Млечный Путь: l=0 → 266.405 / −28.936, l=180 → 86.405 / +28.936")
    func milkyWayCheckpoints() throws {
        let f = try ParityFixtures.load("milkyway.json", as: ParityFixtures.MilkyWayFile.self)
        let deg = 180.0 / Double.pi
        func point(_ l: Double) -> [Double]? { f.band.first { $0[0] == l } }

        let zero = try #require(point(0))
        #expect(abs((zero[2] * deg).truncatingRemainder(dividingBy: 360) - 266.405) < 1e-3)
        #expect(abs(zero[3] * deg + 28.936) < 1e-3)

        let half = try #require(point(180))
        #expect(abs((half[2] * deg).truncatingRemainder(dividingBy: 360) - 86.405) < 1e-3)
        #expect(abs(half[3] * deg - 28.936) < 1e-3)

        /* Полуширина полосы: у ядра около 11.5°, у антицентра втрое уже. */
        #expect(abs(zero[1] - 11.5) < 1e-9)
        #expect(abs(half[1] - 3) < 1e-9)
    }

    @Test("Луна: высоты в пределах круга, расстояние в разумных километрах")
    func moonValuesAreSane() throws {
        let f = try ParityFixtures.load("moon.json", as: ParityFixtures.MoonFile.self)
        for s in f.series {
            #expect(s.alt.count == s.t.count && s.az.count == s.t.count && s.dist.count == s.t.count)
            #expect(s.alt.allSatisfy { $0 >= -90 && $0 <= 90 })
            #expect(s.az.allSatisfy { $0 >= 0 && $0 < 360 })
            #expect(s.dist.allSatisfy { $0 > 350_000 && $0 < 410_000 })
        }
    }
}
