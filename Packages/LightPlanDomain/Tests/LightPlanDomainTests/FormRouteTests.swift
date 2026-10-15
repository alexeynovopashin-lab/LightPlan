import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Место, точки дня и пожелания к погоде в форме (итерация 24, шаг 2).
@Suite struct FormRouteTests {
    let day = CivilDate(year: 2026, month: 10, day: 3)
    let home = RepeatHome(town: "Томск", latitude: 56.48, longitude: 84.95)
    let garden: Spot = { var s = Spot(id: "sp1", name: "Лагерный сад", latitude: 56.45, longitude: 84.96); s.address = "пр. Ленина"; s.town = "Томск"; return s }()
    let lumen: Studio = {
        var s = Studio(id: "st1", name: "Люмен", latitude: 56.47, longitude: 84.97)
        s.address = "Нахимова, 8"; s.town = "Томск"
        s.halls = [Studio.Hall(id: "h1", name: "Белый"), Studio.Hall(id: "h2", name: "Чёрный")]
        return s
    }()

    func fresh(_ g: Genre) -> EventForm {
        EventForm.new(id: "x1", day: day, start: 900, fromLight: false, genre: g, light: nil, home: home)
    }

    @Test func weddingStartsWithThreeHintsThatNeverSave() {
        let f = fresh(.wedding)
        #expect(f.route.count == 3 && f.routeSeeded)
        #expect(!f.hasTypedContent, "подсказки — не набранное")
        let s = f.session(orgName: nil, and: " и ")
        #expect(s.route.isEmpty && s.place.isEmpty)
        #expect(s.latitude == home.latitude && s.placeTown == "Томск", "опора есть — город в записи (веб `placeTownOut`)")
        var bare = EventForm.new(id: "x2", day: day, start: 900, fromLight: false, genre: .portrait, light: nil)
        #expect(bare.session(orgName: nil, and: " и ").placeTown.isEmpty)
        bare.setCity("Москва")
        #expect(bare.session(orgName: nil, and: " и ").placeTown == "Москва", "набранный руками город идёт и без точки")
        #expect(fresh(.portrait).route.isEmpty == !GenreProfile(.portrait).hasRoute)
    }

    @Test func genreSwitchSwapsOnlySeededStops() {
        var f = fresh(.wedding)
        f.pick(.product, sub: nil, prefs: nil, light: nil)
        #expect(f.route.count == (GenreProfile(.product).hasRoute ? 3 : 0))
        var g = fresh(.wedding)
        g.editStop(1) { $0.name = "ЗАГС" }
        g.pick(.product, sub: nil, prefs: nil, light: nil)
        #expect(g.route[1].name == "ЗАГС", "набранное жанр не стирает")
    }

    @Test func firstStopIsThePlaceOfTheShoot() {
        var f = fresh(.wedding)
        f.setStopPlace(0, spot: garden, spots: [garden], studios: [])
        #expect(f.sessionPlace.name == "Лагерный сад" && f.sessionPlace.latitude == 56.45 && f.sessionPlace.address == "пр. Ленина")
        f.setStopStudio(1, studio: lumen, studioWord: "Фотостудия", spots: [garden], studios: [lumen])
        #expect(f.route[1].name == "Фотостудия" && f.route[1].placeText == "Люмен")
        f.setStopHall(1, hall: lumen.halls[0], label: { "\($0), зал \($1)" }, spots: [garden], studios: [lumen])
        #expect(f.route[1].placeText == "Люмен, зал Белый" && f.route[1].hallId == "h1")
        #expect(f.sessionPlace.name == "Лагерный сад", "вторая точка место съёмки не трогает")
        f.removeStop(0, spots: [garden], studios: [lumen])
        #expect(f.sessionPlace.name == "Люмен, зал Белый" && f.sessionPlace.latitude == 56.47)
        let s = f.session(orgName: nil, and: " и ", studios: [lumen])
        #expect(s.studioId == "st1" && s.hallId == "h1" && s.place == "Люмен, зал Белый")
    }

    @Test func emptyFirstStopDoesNotHideTheStudio() {
        var f = fresh(.wedding)
        f.setStopStudio(1, studio: lumen, studioWord: "Фотостудия", spots: [], studios: [lumen])
        #expect(f.route[0].placeText.isEmpty, "первая заготовка осталась пустой")
        let s = f.session(orgName: nil, and: " и ", studios: [lumen])
        #expect(s.route.first?.studioId == "st1")
        #expect(s.studioId == "st1" && s.place == "Люмен" && s.latitude == 56.47 && s.placeAddress == "Нахимова, 8",
                "место и студия — с первой сохранённой точки, а не с пустой заготовки")
        var g = fresh(.wedding)
        g.setStopPlace(2, spot: garden, spots: [garden], studios: [])
        let t = g.session(orgName: nil, and: " и ", spots: [garden])
        #expect(t.place == "Лагерный сад" && t.latitude == 56.45 && t.studioId == nil)
    }

    // MARK: - 29.11, пункт 1: часы студии — часы съёмки

    @Test func studioStopTakesTheShootWindow() {
        // Съёмка 13:00–14:00 (слово Алексея 14.10): студия в точке встаёт на те же часы.
        var f = EventForm.new(id: "x3", day: day, start: 780, fromLight: false, genre: .portrait, light: nil, home: home)
        f.duration = 60
        f.addStop()
        f.setStopStudio(0, studio: lumen, studioWord: "Фотостудия", spots: [], studios: [lumen])
        #expect(f.route[0].start == 780 && f.route[0].end == 840)
        #expect(f.session(orgName: nil, and: " и ", studios: [lumen]).rentFrom == 780)
    }

    @Test func studioStopKeepsHoursThePhotographerSet() {
        var f = EventForm.new(id: "x4", day: day, start: 780, fromLight: false, genre: .portrait, light: nil, home: home)
        f.duration = 60
        f.addStop()
        f.setStopTime(0, end: false, minute: 690, hint: "Старт")
        f.setStopTime(0, end: true, minute: 735, hint: "Старт")
        f.setStopStudio(0, studio: lumen, studioWord: "Фотостудия", spots: [], studios: [lumen])
        #expect(f.route[0].start == 690 && f.route[0].end == 735, "своё время точки не затирается")
        // Одно из двух поставлено — второе тоже не выдумывается.
        var g = f
        g.editStop(0) { $0.end = nil }
        g.setStopStudio(0, studio: lumen, studioWord: "Фотостудия", spots: [], studios: [lumen])
        #expect(g.route[0].start == 690 && g.route[0].end == nil)
    }

    @Test func studioStopFollowsTheShootUntilTouched() {
        // Причина 14:15–14:40 при съёмке 15:15–16:15: точку поставили на часы
        // съёмки, съёмку подвинули, а точка осталась на прежних.
        var f = EventForm.new(id: "x5", day: day, start: 855, fromLight: false, genre: .portrait, light: nil, home: home)
        f.duration = 60
        f.addStop()
        f.setStopStudio(0, studio: lumen, studioWord: "Фотостудия", spots: [], studios: [lumen])
        #expect(f.route[0].start == 855 && f.route[0].end == 915)
        f.setStart(minute: 915)
        #expect(f.route[0].start == 915 && f.route[0].end == 975, "съёмка 15:15–16:15 — студия там же")
        f.setEnd(dayOffset: 0, minuteOfDay: 1050)
        #expect(f.route[0].end == 1050, "конец съёмки тянет конец точки")
        // Своё время точки съёмка не двигает.
        f.setStopTime(0, end: false, minute: 930, hint: "Старт")
        f.setStart(minute: 960)
        #expect(f.route[0].start == 930)
    }

    @Test func manualHoursEqualToTheShootWindowDoNotFollow() {
        // Фотограф сам поставил ровно время съёмки: это его выбор, а не «время съёмки» (29.11б).
        var f = EventForm.new(id: "x8", day: day, start: 780, fromLight: false, genre: .portrait, light: nil, home: home)
        f.duration = 60
        f.addStop()
        f.setStopTime(0, end: false, minute: 780, hint: "Старт")
        f.setStopTime(0, end: true, minute: 840, hint: "Старт")
        f.setStopStudio(0, studio: lumen, studioWord: "Фотостудия", spots: [], studios: [lumen])
        #expect(!f.route[0].hoursAuto)
        f.setStart(minute: 900)
        #expect(f.route[0].start == 780 && f.route[0].end == 840, "ручные часы не едут")
        // Автоматические — едут; ручная правка снимает признак.
        var g = EventForm.new(id: "x9", day: day, start: 780, fromLight: false, genre: .portrait, light: nil, home: home)
        g.duration = 60
        g.addStop()
        g.setStopStudio(0, studio: lumen, studioWord: "Фотостудия", spots: [], studios: [lumen])
        #expect(g.route[0].hoursAuto)
        g.setStart(minute: 900)
        #expect(g.route[0].start == 900 && g.route[0].end == 960)
        g.setStopTime(0, end: false, minute: 900, hint: "Старт")
        #expect(!g.route[0].hoursAuto, "тот же час, набранный руками, — уже ручной")
        g.setStart(minute: 1000)
        #expect(g.route[0].start == 900)
    }

    @Test func hoursOriginSurvivesDraftAndOldRecordsAreManual() throws {
        var f = EventForm.new(id: "x10", day: day, start: 780, fromLight: false, genre: .portrait, light: nil, home: home)
        f.duration = 60
        f.addStop()
        f.setStopStudio(0, studio: lumen, studioWord: "Фотостудия", spots: [], studios: [lumen])
        let data = try #require(f.draftData())
        let back = try #require(EventForm.fromDraft(data))
        #expect(back.route[0].hoursAuto, "признак переживает черновик")
        // Запись без ключа (до 29.11б) — ручные часы.
        let old = try JSONDecoder().decode(RoutePoint.self, from: Data(#"{"t":780,"t2":840,"n":"","p":"Люмен","studioId":"st1"}"#.utf8))
        #expect(!old.hoursAuto)
        let new = try JSONEncoder().encode(f.route[0])
        #expect(try JSONDecoder().decode(RoutePoint.self, from: new).hoursAuto)
    }

    @Test func stopWithOwnEndDoesNotFollowOnSharedStart() {
        // Начало точки совпало с началом съёмки, а конец — свой: это уже не «время съёмки».
        var f = EventForm.new(id: "x7", day: day, start: 780, fromLight: false, genre: .portrait, light: nil, home: home)
        f.duration = 60
        f.addStop()
        f.setStopStudio(0, studio: lumen, studioWord: "Фотостудия", spots: [], studios: [lumen])
        f.setStopTime(0, end: true, minute: 810, hint: "Старт")
        f.setStart(minute: 900)
        #expect(f.route[0].start == 780 && f.route[0].end == 810, "частичное совпадение точку не двигает")
    }

    @Test func bookedStudioStopStaysWhereTheBookingPut() {
        var f = EventForm.new(id: "x6", day: day, start: 780, fromLight: false, genre: .portrait, light: nil, home: home)
        f.duration = 60
        f.addStop()
        f.setStopStudio(0, studio: lumen, studioWord: "Фотостудия", spots: [], studios: [lumen])
        f.applyBooking(ref: "B1", hallId: "h1", start: 780, end: 840,
                       label: { "\($0), зал \($1)" }, spots: [], studios: [lumen])
        f.setStart(minute: 900)
        #expect(f.route[0].start == 780 && f.route[0].end == 840, "бронь — факт студии, съёмка его не двигает")
    }

    @Test func stopTimeTakesHintAsName() {
        var f = fresh(.wedding)
        #expect(f.stopTimeSeed(0, end: false) == 900)
        f.setStopTime(0, end: false, minute: 900, hint: "Сборы")
        f.setStopTime(0, end: true, minute: 960, hint: "Сборы")
        #expect(f.stopTimeSeed(1, end: false) == 990, "полчаса после конца прошлой точки")
        let s = f.session(orgName: nil, and: " и ")
        #expect(s.route == [RoutePoint(start: 900, end: 960, name: "Сборы")])
    }

    @Test func routeRoundTripsThroughTheRecord() {
        var f = fresh(.wedding)
        f.setStopPlace(0, spot: garden, spots: [garden], studios: [])
        f.setStopTime(0, end: false, minute: 900, hint: "Сборы")
        f.editStop(1) { $0.name = "ЗАГС"; $0.placeText = "Дворец" }
        f.addStop()
        f.toggle(wish: .sunset); f.toggle(wish: .clear)
        let s = f.session(orgName: nil, and: " и ")
        #expect(s.route.count == 2 && s.wishes == [.sunset, .clear])
        let back = EventForm.editing(s)
        #expect(back.route == s.route && back.sessionPlace.name == "Лагерный сад" && back.wishes == s.wishes)
        #expect(back.session(orgName: nil, and: " и ", now: Date(timeIntervalSince1970: 0)).route == s.route)
    }

    @Test func oldRecordPlaceBecomesFirstStop() {
        var base = Session(id: "r1", day: day, start: 600, duration: 90, genre: .portrait)
        base.place = "Набережная"; base.latitude = 56.5; base.longitude = 84.9
        base.route = [RoutePoint(start: 660, name: "Кафе")]
        let f = EventForm.editing(base)
        #expect(f.route.count == 2 && f.route[0].placeText == "Набережная" && f.route[0].start == 600 && f.route[0].end == 690)
        // Место уже стоит первой точкой — второй раз не встаёт.
        let again = EventForm.editing(f.session(orgName: nil, and: " и "))
        #expect(again.route.count == 2)
    }

    @Test func draftKeepsRouteAndWishes() throws {
        var f = fresh(.wedding)
        f.setStopPlace(0, spot: garden, spots: [garden], studios: [])
        f.toggle(wish: .stars)
        #expect(f.hasTypedContent)
        let data = try #require(f.draftData())
        let back = try #require(EventForm.fromDraft(data))
        #expect(back.route == f.route && back.sessionPlace == f.sessionPlace && back.wishes == f.wishes && back.routeSeeded == f.routeSeeded)
    }

    @Test func anyClearsWishes() {
        var f = fresh(.portrait)
        f.toggle(wish: .fog); f.toggle(wish: .rain)
        #expect(!f.wishOn(.any))
        f.toggle(wish: .any)
        #expect(f.wishes.isEmpty && f.wishOn(.any))
    }

    // MARK: замысел против прогноза — ветви веба `wishCheck`

    func sky(_ q: DayQuality, sunset: Int? = nil, night: Bool = true, moon: Int? = 0, pct: Int? = 0, frac: Double = 0.5) -> WishSky {
        WishSky(quality: q, sunsetScore: sunset, astroNight: night, moonLevel: moon, moonPercent: pct, moonFraction: frac)
    }

    /// 28ж: нет настоящего прогноза — пожелания про погоду молчат (выдумка не судья),
    /// пожелания про астрономию — луна, белая ночь, городское зарево — работают.
    @Test func noForecastSilencesWeatherWishesOnly() {
        func none(night: Bool = true, frac: Double = 0.5, moon: Int? = 0) -> WishSky {
            WishSky(quality: nil, sunsetScore: nil, astroNight: night, moonLevel: moon, moonPercent: 10, moonFraction: frac)
        }
        for w in [Wish.clear, .cloudy, .fog, .rain, .sunset] {
            #expect(WishCheck.check(w, sky: none(), city: false) == nil, "\(w): погодное пожелание без прогноза")
        }
        #expect(WishCheck.check(.stars, sky: none(), city: false) == nil)
        #expect(WishCheck.check(.moon, sky: none(), city: false) == nil)
        #expect(WishCheck.check(.stars, sky: none(night: false), city: false)?.key == "whiteNight")
        #expect(WishCheck.check(.stars, sky: none(), city: true)?.key == "cityGlow")
        #expect(WishCheck.check(.stars, sky: none(moon: 2), city: false)?.key == "moonWash")
        #expect(WishCheck.check(.moon, sky: none(frac: 0.1), city: false)?.key == "newMoon")
    }

    @Test func wishCheckBranches() {
        #expect(WishCheck.check(.stars, sky: sky(.excellent, night: false), city: false)?.key == "whiteNight")
        #expect(WishCheck.check(.stars, sky: sky(.good), city: false)?.key == "noStars")
        #expect(WishCheck.check(.stars, sky: sky(.excellent), city: true)?.key == "cityGlow")
        #expect(WishCheck.check(.stars, sky: sky(.excellent, moon: 2, pct: 80), city: false)?.params["pct"] == "80")
        #expect(WishCheck.check(.stars, sky: sky(.excellent), city: false) == nil)
        #expect(WishCheck.check(.sunset, sky: sky(.good, sunset: 40), city: false)?.key == "dullSunset")
        #expect(WishCheck.check(.sunset, sky: sky(.poor), city: false)?.key == "noSunset")
        #expect(WishCheck.check(.sunset, sky: sky(.poor, sunset: 70), city: false) == nil, "балл прогноза главнее неба")
        #expect(WishCheck.check(.rain, sky: sky(.good), city: false)?.key == "noRain")
        #expect(WishCheck.check(.moon, sky: sky(.good, frac: 0.1), city: false)?.params["pct"] == "10")
        #expect(WishCheck.check(.clear, sky: sky(.good), city: false)?.wish == .clear)
        #expect(WishCheck.check(.cloudy, sky: sky(.good), city: false) == nil)
        #expect(WishCheck.first([.cloudy, .rain], sky: sky(.good), city: false)?.key == "noRain")
    }
}
