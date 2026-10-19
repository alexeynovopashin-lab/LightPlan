import Testing
import Foundation
import LightPlanCore

/// Звёзды и созвездия слоя AR (шаг 29.8в.13): место на небе, видимость по солнцу, горизонт, фигуры.
struct StarSkyARTests {

    static let tomsk = Place(latitude: 56.4977, longitude: 84.9744, zone: ZoneID("Asia/Tomsk")!)
    static let viewport = ScreenViewport(width: 393, height: 852)

    /// Угол между двумя точками неба, градусы.
    private func separation(_ a: HorizontalPoint, _ b: HorizontalPoint) -> Double {
        let u = SkyVector(azimuth: a.azimuth, altitude: a.altitude), v = SkyVector(azimuth: b.azimuth, altitude: b.altitude)
        return acos(min(1, max(-1, u.dot(v)))) * 180 / Double.pi
    }

    private func position(of star: String, day: CivilDate, minutes: Minutes) -> HorizontalPoint {
        let cat = StarCatalogAR.current
        let i = cat.stars.firstIndex { $0.nameKey == star }!
        return StarSkyAR.horizontals(day: day, minutes: minutes, in: Self.tomsk)[i]
    }

    // MARK: - Каталог

    @Test("каталог слоя: 163 звезды фигур — 161 уникальная (Альферац и Эльнат стоят в двух созвездиях) и 31 яркая вне фигур, линии ссылаются на номера")
    func catalogShape() {
        let cat = StarCatalogAR.current
        #expect(StarCatalogAR(constellations: ConstellationCatalog.all).stars.count == 161)
        #expect(BrightStarCatalog.all.count == 31)
        #expect(cat.stars.count == 161 + 31)
        #expect(cat.figures.count == 24)
        for f in cat.figures {
            #expect(f.lines.allSatisfy { $0.count == 2 && $0.allSatisfy { cat.stars.indices.contains($0) } })
            #expect(f.stars.allSatisfy { cat.stars.indices.contains($0) })
        }
        let and = cat.figures.first { $0.code == "And" }!, peg = cat.figures.first { $0.code == "Peg" }!
        #expect(!Set(and.stars).isDisjoint(with: Set(peg.stars)))
    }

    @Test("22 имени: у каждого в каталоге ровно одна звезда, и это все звёзды слоя до величины 1,5 (Канопус, Акрукс, Бекрукс — тоже)")
    func namesMatchOnce() {
        let cat = StarCatalogAR.current
        for n in StarName.brightest {
            let hits = cat.stars.filter { abs($0.ra - n.ra) < 1e-9 && abs($0.dec - n.dec) < 1e-9 && $0.nameKey == n.key }
            #expect(hits.count == 1, "\(n.key)")
        }
        let named = cat.stars.filter { $0.nameKey != nil }
        #expect(named.count == 22 && Set(named.map(\.nameKey)).count == 22)
        #expect(Set(named.map(\.nameKey)) == Set(cat.stars.filter { $0.magnitude <= StarName.limit }.map(\.nameKey)))
        // Следующая по блеску — уже слабее предела: подпись не обрывается посреди одинаково ярких звёзд.
        #expect(cat.stars.filter { $0.nameKey == nil }.map(\.magnitude).min()! > StarName.limit)
    }

    @Test("одна звезда — одна точка: в каталоге слоя нет двух звёзд ближе 0,05°; звезда, которая уже взята, второй раз не добавляется")
    func noDuplicates() {
        let cat = StarCatalogAR.current
        func dir(_ s: SkyStar) -> (Double, Double, Double) {
            let a = s.ra * Double.pi / 12, d = s.dec * Double.pi / 180
            return (cos(d) * cos(a), cos(d) * sin(a), sin(d))
        }
        let v = cat.stars.map(dir)
        var closest = 180.0
        for i in v.indices { for j in v.indices where j > i {
            let c = v[i].0 * v[j].0 + v[i].1 * v[j].1 + v[i].2 * v[j].2
            closest = min(closest, acos(min(1, max(-1, c))) * 180 / Double.pi)
        } }
        #expect(closest >= StarCatalogAR.sameStar, "ближайшая пара \(closest)°")
        // Яркие звёзды поданы дважды: точек столько же, у Канопуса одно имя.
        let doubled = StarCatalogAR(constellations: ConstellationCatalog.all, bright: BrightStarCatalog.all + BrightStarCatalog.all)
        #expect(doubled.stars.count == cat.stars.count)
        #expect(doubled.stars.filter { $0.nameKey == "star.canopus" }.count == 1)
    }

    static let sydney = Place(latitude: -33.8688, longitude: 151.2093, zone: ZoneID("Australia/Sydney")!)

    @Test("южная ночь (Сидней, 15.06.2026 22:00): Канопус и три звезды Южного Креста — в сцене, каждая одной точкой и с одним именем")
    func southernNight() throws {
        let day = CivilDate(year: 2026, month: 6, day: 15)
        let cat = StarCatalogAR.current
        let pos = StarSkyAR.horizontals(day: day, minutes: 1320, in: Self.sydney)
        func index(ra: Double) throws -> Int { try #require(cat.stars.firstIndex { abs($0.ra - ra) < 1e-9 }, "нет звезды RA \(ra)") }
        let canopus = try index(ra: 6.39919), acrux = try index(ra: 12.44331), mimosa = try index(ra: 12.79533)
        let gacrux = try index(ra: 12.51942)
        // Канопус низко на юге (≈ 3,8°), Крест высоко (≈ 50°).
        #expect(pos[canopus].altitude > 2 && pos[canopus].altitude < 6, "\(pos[canopus])")
        for i in [acrux, mimosa, gacrux] { #expect(pos[i].altitude > 40, "\(pos[i])") }
        for (aim, want) in [(pos[canopus], [canopus]), (pos[mimosa], [acrux, mimosa, gacrux])] {
            let s = scene(positions: pos, catalog: cat, aim: aim, figures: false)
            for i in want { #expect(s.dots.filter { $0.index == i }.count == 1, "звезда \(i) не одна или её нет") }
            let keys = s.dots.compactMap(\.nameKey)
            #expect(keys.count == Set(keys).count, "имя дважды: \(keys)")
        }
        let cross = scene(positions: pos, catalog: cat, aim: pos[mimosa], figures: false).dots
        #expect(cross.contains { $0.nameKey == "star.acrux" } && cross.contains { $0.nameKey == "star.mimosa" })
        #expect(scene(positions: pos, catalog: cat, aim: pos[canopus], figures: false).dots.contains { $0.nameKey == "star.canopus" })
        // Цвет — по спектральному классу: Гакрукс (M3.5III) теплее Акрукса (B0.5IV).
        #expect(cat.stars[gacrux].spectralClass == "M" && cat.stars[acrux].spectralClass == "B")
    }

    // MARK: - Положение

    @Test("Полярная звезда стоит на высоте широты места ±1° в любой час и день (Томск 56,50°)")
    func polarisAtLatitude() {
        let cat = StarCatalogAR.current
        let i = cat.stars.firstIndex { abs($0.dec - 89.26) < 0.01 }!
        let days = [CivilDate(year: 2026, month: 1, day: 1), CivilDate(year: 2026, month: 4, day: 5),
                    CivilDate(year: 2026, month: 7, day: 9), CivilDate(year: 2026, month: 10, day: 14),
                    CivilDate(year: 2027, month: 1, day: 20)]
        for day in days {
            for minutes in stride(from: 0.0, to: 1440, by: 180) {
                let p = StarSkyAR.horizontals(day: day, minutes: minutes, in: Self.tomsk)[i]
                #expect(abs(p.altitude - 56.4977) < 1, "\(day.day).\(day.month).\(day.year) \(minutes): \(p.altitude)")
            }
        }
    }

    /// Эталон: astropy 6.0.1, ICRS → AltAz (с прецессией, нутацией и аберрацией, без рефракции), место 56,4977° с. ш.
    /// 84,9744° в. д., координаты звёзд — Yale Bright Star Catalog (VizieR V/50). Момент — UTC; Томск UTC+7.
    private static let reference: [(star: String, day: CivilDate, minutes: Minutes, alt: Double, az: Double)] = [
        ("star.sirius", CivilDate(year: 2026, month: 12, day: 22), 300, 8.097, 222.087),
        ("star.vega", CivilDate(year: 2026, month: 10, day: 20), 1260, 56.003, 257.922),
        ("star.vega", CivilDate(year: 2027, month: 3, day: 10), 480, 70.611, 150.794),
        ("star.arcturus", CivilDate(year: 2026, month: 12, day: 22), 300, 27.461, 96.809),
        ("star.arcturus", CivilDate(year: 2027, month: 3, day: 10), 480, 35.771, 248.928),
        ("star.capella", CivilDate(year: 2026, month: 10, day: 20), 1260, 25.733, 44.010),
        ("star.capella", CivilDate(year: 2026, month: 12, day: 22), 300, 49.231, 284.157),
        ("star.betelgeuse", CivilDate(year: 2026, month: 12, day: 22), 300, 24.287, 244.830),
        ("star.deneb", CivilDate(year: 2026, month: 10, day: 20), 1260, 76.079, 222.709),
        ("star.deneb", CivilDate(year: 2026, month: 12, day: 22), 300, 12.639, 10.652),
    ]

    @Test("звёзды на небе Томска — по эталону astropy в пределах 1° (наибольшее расхождение печатается)")
    func againstReference() {
        var worst = 0.0
        for r in Self.reference {
            let p = position(of: r.star, day: r.day, minutes: r.minutes)
            let d = separation(p, HorizontalPoint(altitude: r.alt, azimuth: r.az))
            worst = max(worst, d)
            #expect(d < 1, "\(r.star) \(r.day) \(r.minutes): расхождение \(d)°, высота \(p.altitude) (эталон \(r.alt)), азимут \(p.azimuth) (\(r.az))")
        }
        print(String(format: "star reference: worst separation %.3f° over %d points", worst, Self.reference.count))
    }

    // MARK: - Горизонт

    private func scene(positions: [HorizontalPoint], catalog: StarCatalogAR, aim: HorizontalPoint, sun: Degrees = -30,
                       stars: Bool = true, figures: Bool = true) -> StarSkyARScene {
        StarSkyAR.make(catalog: catalog, positions: positions, sunAltitude: sun,
                       basis: CameraBasis(azimuth: aim.azimuth, altitude: aim.altitude), optics: .typical,
                       viewport: Self.viewport, stars: stars, constellations: figures)
    }

    @Test("звезда под горизонтом не рисуется, хотя камера смотрит на неё; над горизонтом — рисуется")
    func belowHorizonNotDrawn() {
        let cat = StarCatalogAR(stars: [SkyStar(ra: 0, dec: 0, magnitude: 1), SkyStar(ra: 0, dec: 0, magnitude: 1)], figures: [])
        let pos = [HorizontalPoint(altitude: -12, azimuth: 100), HorizontalPoint(altitude: 8, azimuth: 100)]
        let s = scene(positions: pos, catalog: cat, aim: HorizontalPoint(altitude: 0, azimuth: 100))
        #expect(s.dots.map(\.index) == [1])
        // Настоящая Сириус ночью 20 октября 21:00 в Томске на −39°: в сцене её нет, даже когда камера направлена в неё.
        let real = StarSkyAR.horizontals(day: CivilDate(year: 2026, month: 10, day: 20), minutes: 1260, in: Self.tomsk)
        let i = StarCatalogAR.current.stars.firstIndex { $0.nameKey == "star.sirius" }!
        #expect(real[i].altitude < -30)
        let aimed = scene(positions: real, catalog: .current, aim: real[i])
        #expect(!aimed.dots.contains { $0.index == i })
    }

    @Test("линия, у которой один конец под горизонтом, обрывается на горизонте; оба под горизонтом — линии нет")
    func segmentCutsAtHorizon() {
        let cat = StarCatalogAR(stars: (0..<3).map { _ in SkyStar(ra: 0, dec: 0, magnitude: 2) },
                                figures: [StarFigure(code: "T", stars: [0, 1, 2], lines: [[0, 1], [1, 2]])])
        let pos = [HorizontalPoint(altitude: 10, azimuth: 90), HorizontalPoint(altitude: -10, azimuth: 90),
                   HorizontalPoint(altitude: -20, azimuth: 90)]
        let s = scene(positions: pos, catalog: cat, aim: HorizontalPoint(altitude: 0, azimuth: 90))
        #expect(s.segments.count == 1)
        // Конец у горизонта лежит в центре кадра, куда смотрит камера (видимая высота 0°, азимут тот же).
        let end = s.segments[0].to
        #expect(abs(end.x - 196.5) < 0.6 && abs(end.y - 426) < 0.6, "\(end)")
        #expect(s.segments[0].from.y < end.y)
    }

    // MARK: - Видимость по солнцу

    @Test("яркость слоя по солнцу: −6° и выше — 0, −12° и ниже — 1, между — растёт плавно и без излома на краях")
    func visibilityBySun() {
        #expect(StarVisibility.opacity(sunAltitude: 40) == 0)
        #expect(StarVisibility.opacity(sunAltitude: -5.9) == 0)
        #expect(StarVisibility.opacity(sunAltitude: -6) == 0)
        #expect(StarVisibility.opacity(sunAltitude: -12) == 1)
        #expect(StarVisibility.opacity(sunAltitude: -40) == 1)
        #expect(abs(StarVisibility.opacity(sunAltitude: -9) - 0.5) < 1e-12)
        var previous = 0.0
        for tenth in stride(from: -60, through: -120, by: -1) {
            let v = StarVisibility.opacity(sunAltitude: Double(tenth) / 10)
            #expect(v >= previous)
            previous = v
        }
        // Нет излома: у краёв шаг на 0,1° меньше 0,01.
        #expect(StarVisibility.opacity(sunAltitude: -6.1) < 0.01 && 1 - StarVisibility.opacity(sunAltitude: -11.9) < 0.01)
        #expect(StarVisibility.isDaylight(sunAltitude: -5.99) && !StarVisibility.isDaylight(sunAltitude: -6.01))
    }

    @Test("днём слои включены, но яркость 0 и сцена знает, что день; ночью яркость 1; в сумерках между")
    func sceneVisibility() {
        let cat = StarCatalogAR.current
        let pos = StarSkyAR.horizontals(day: CivilDate(year: 2026, month: 12, day: 22), minutes: 300, in: Self.tomsk)
        let aim = HorizontalPoint(altitude: 30, azimuth: 150)
        let day = scene(positions: pos, catalog: cat, aim: aim, sun: 25)
        #expect(day.visibility == 0 && day.daylight && day.isOn)
        let dusk = scene(positions: pos, catalog: cat, aim: aim, sun: -9)
        #expect(dusk.visibility > 0 && dusk.visibility < 1 && !dusk.daylight)
        let night = scene(positions: pos, catalog: cat, aim: aim, sun: -20)
        #expect(night.visibility == 1 && !night.daylight)
    }

    // MARK: - Слои, вид точки

    @Test("флаги слоёв: «Звёзды» — точки без линий, «Созвездия» — линии и подписи без точек, оба выключены — пусто")
    func layerFlags() {
        let pos = StarSkyAR.horizontals(day: CivilDate(year: 2026, month: 12, day: 22), minutes: 300, in: Self.tomsk)
        let aim = HorizontalPoint(altitude: 35, azimuth: 150)
        let both = scene(positions: pos, catalog: .current, aim: aim)
        #expect(!both.dots.isEmpty && !both.segments.isEmpty && !both.figures.isEmpty)
        let starsOnly = scene(positions: pos, catalog: .current, aim: aim, figures: false)
        #expect(!starsOnly.dots.isEmpty && starsOnly.segments.isEmpty && starsOnly.figures.isEmpty)
        let figuresOnly = scene(positions: pos, catalog: .current, aim: aim, stars: false)
        #expect(figuresOnly.dots.isEmpty && !figuresOnly.segments.isEmpty && !figuresOnly.figures.isEmpty)
        let none = scene(positions: pos, catalog: .current, aim: aim, stars: false, figures: false)
        #expect(!none.isOn && none.dots.isEmpty && none.segments.isEmpty && none.figures.isEmpty)
    }

    @Test("радиус и яркость точки растут с блеском; Сириус крупнее и ярче слабой звезды; без спектрального класса — белый")
    func look() {
        #expect(StarLook.radius(magnitude: -1.46) > StarLook.radius(magnitude: 0))
        #expect(StarLook.radius(magnitude: 0) > StarLook.radius(magnitude: 2))
        #expect(StarLook.radius(magnitude: 2) > StarLook.radius(magnitude: 5) || StarLook.radius(magnitude: 5) == 0.8)
        #expect(StarLook.radius(magnitude: 6) == 0.8)
        #expect(StarLook.brightness(magnitude: -1.46) == 1 && StarLook.brightness(magnitude: 6) == 0.4)
        #expect(StarLook.brightness(magnitude: 1) > StarLook.brightness(magnitude: 3))
        let white = StarLook.tint(spectralClass: nil)
        #expect(white.red == 1 && white.green == 1 && white.blue == 1)
        let b = StarLook.tint(spectralClass: "B"), m = StarLook.tint(spectralClass: "m")
        #expect(b.blue > b.red && m.red > m.blue)
        // «Почти белый»: ни один канал не ниже 0,6.
        for c in "OBAFGKM" { let t = StarLook.tint(spectralClass: c); #expect(min(t.red, t.green, t.blue) >= 0.6) }
    }

    @Test("подпись созвездия — у центра фигуры по небу; фигура, у которой над горизонтом меньше 60 % звёзд, подписи не получает")
    func figureLabel() {
        let cat = StarCatalogAR(stars: (0..<4).map { _ in SkyStar(ra: 0, dec: 0, magnitude: 2) },
                                figures: [StarFigure(code: "T", stars: [0, 1, 2, 3], lines: [[0, 1], [2, 3]])])
        let up = [HorizontalPoint(altitude: 30, azimuth: 80), HorizontalPoint(altitude: 30, azimuth: 100),
                  HorizontalPoint(altitude: 40, azimuth: 80), HorizontalPoint(altitude: 40, azimuth: 100)]
        let s = scene(positions: up, catalog: cat, aim: HorizontalPoint(altitude: 35, azimuth: 90))
        #expect(s.figures.count == 1)
        // Центр — между звёздами: по экрану почти в центре кадра.
        #expect(abs(s.figures[0].point.x - 196.5) < 12 && abs(s.figures[0].point.y - 426) < 12, "\(s.figures[0].point)")
        var half = up
        half[2] = HorizontalPoint(altitude: -20, azimuth: 80); half[3] = HorizontalPoint(altitude: -20, azimuth: 100)
        // Над горизонтом половина звёзд (50 % < 60 %) — подписи нет; три из четырёх (75 %) — подпись есть.
        #expect(scene(positions: half, catalog: cat, aim: HorizontalPoint(altitude: 35, azimuth: 90)).figures.isEmpty)
        var most = up
        most[3] = HorizontalPoint(altitude: -20, azimuth: 100)
        #expect(scene(positions: most, catalog: cat, aim: HorizontalPoint(altitude: 35, azimuth: 90)).figures.count == 1)
    }
}
