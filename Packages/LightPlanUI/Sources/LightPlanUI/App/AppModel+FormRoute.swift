import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Место, точки дня и пожелания к погоде в форме (итерация 24, шаг 2). Правила —
/// в `EventForm` (`FormRoute.swift`), здесь — связка с «Моими местами», студиями,
/// листом «Где снимаем» и небом приложения.
extension AppModel {

    public var studios: [Studio] { snapshot.studios }

    // MARK: - Точки

    /// Лист «Где снимаем» для точки `i`, сразу на пути `way` (веб `openLocSheet("stop", way, i)`).
    func openStopPlace(_ i: Int, way: PlaceSheetForm.Way, openCard: Bool = false) {
        placeSheetStart = way
        placeSheetOpenCard = openCard
        placeSheetStop = i
    }

    public func setFormStopPlace(_ i: Int, spot: Spot) {
        formEdit { $0.setStopPlace(i, spot: spot, spots: snapshot.spots, studios: snapshot.studios) }
    }

    public func setFormStopStudio(_ i: Int, studio: Studio) {
        formEdit {
            $0.setStopStudio(i, studio: studio, studioWord: lexicon.t("loc.wayStudio"),
                             spots: snapshot.spots, studios: snapshot.studios)
        }
    }

    public func setFormStopHall(_ i: Int, hall: Studio.Hall?) {
        formEdit {
            $0.setStopHall(i, hall: hall, label: { [lexicon] in lexicon.t("form.placeHall", ["place": $0, "hall": $1]) },
                           spots: snapshot.spots, studios: snapshot.studios)
        }
    }

    public func addFormStop() { formEdit { $0.addStop() } }

    public func removeFormStop(_ i: Int) {
        formEdit { $0.removeStop(i, spots: snapshot.spots, studios: snapshot.studios, home: repeatHome) }
    }

    /// Имя точки набрано руками.
    public func setFormStopName(_ i: Int, _ v: String) { formEdit { $0.editStop(i) { $0.name = v } } }

    /// Место набрано руками: ссылка на место рвётся (веб `.rt-in-p` input).
    public func setFormStopPlaceText(_ i: Int, _ v: String) {
        formEdit {
            $0.editStop(i, spots: snapshot.spots, studios: snapshot.studios, home: repeatHome) {
                $0.placeText = v; $0.spotId = nil; $0.studioId = nil; $0.hallId = nil
            }
        }
    }

    public func setFormStopTime(_ i: Int, end: Bool, minute: Int) {
        guard let g = form?.genre else { return }
        let hint = lexicon.t("scene." + SceneHints.key(g, i))
        formEdit { $0.setStopTime(i, end: end, minute: minute, hint: hint) }
    }

    public func setFormCity(_ v: String) { formEdit { $0.setCity(v) } }

    // MARK: - Пожелания

    public func toggleFormWish(_ w: Wish) {
        guard var f = form else { return }
        // «Неважно» стирает видимые пожелания, а скрытую «Луну» (30г.6) не трогает: данные не меняются от того, что их не видно.
        let shown = Set(shownWishes(f.wishes))
        let hidden = w == .any ? f.wishes.filter { !shown.contains($0) } : []
        formTimeAsk = f.toggleWish(w) { self.formTimeFacts($0) }
        f.wishes += hidden
        form = f
        formChanged()
    }

    /// Небо дня для проверки пожеланий. Погода (31.6б) — у места съёмки, тем же путём, что у карточки (`formDay`); места
    /// у формы нет — у места приложения, как у веба (`qualityOf`, `dayWeather` смотрят на `LAT`/`LON`). Темнота и луна (31.6в) —
    /// тоже у места съёмки, теми же правилами, что строка «Звёзды» карточки (`starNightIsDark`, `MoonVsStars`). Прогноз места
    /// ещё летит — пожелания про погоду молчат, как карточка, пока его нет.
    func wishSky(_ day: CivilDate, form f: EventForm? = nil) -> WishSky {
        let s = f.flatMap(formSession)
        let wx = formDay(s, day)      // `nil` — прогноза нет: пожелания про погоду молчат
        // «Звёзды» — небом ночи (`starClouds`, одно с карточкой): часы съёмки, если время назвал человек; предложенное правилом —
        // часы ночи (окно Млечного Пути, нет окна — темнота ниже −18°, 31.6в).
        let night = f.flatMap { f in f.wishes.contains(.stars) ? s.flatMap { starClouds($0, timed: !f.timeIsProposed) } : nil }
        let p = cardPlace(s.flatMap(anchor))
        let moon = MoonVsStars(date: day, place: p)
        return WishSky(quality: wx?.quality, sunsetScore: wx?.sunset, astroNight: starNightIsDark(day, p),
                       moonLevel: moon.level?.rawValue, moonPercent: moon.percent,
                       moonFraction: MoonPhase(date: day, minutes: 1320, zone: p.zone).fraction,
                       shootMoon: f.flatMap(shootMoon), dawnFog: wx?.dawnFog ?? false,
                       sunriseScore: wx?.sunrise, dawnQuality: wx?.dawnQuality, atDawn: f.map(formShootsAtDawn) ?? false,
                       nightSky: night)
    }

    /// Запись, которую соберёт форма, — для правил карточки (место, утро, луна). Дня у формы нет — `nil`.
    func formSession(_ f: EventForm) -> Session? {
        guard !f.dayUnset else { return nil }
        return f.session(orgName: nil, and: "", studios: snapshot.studios, spots: snapshot.spots, homeCity: homeCityName, now: now())
    }

    /// Прогноз суток для формы (31.6б): у места съёмки — функция карточки `shootDay`; места нет — место приложения.
    func formDay(_ s: Session?, _ d: CivilDate) -> WeatherDay? { formDay(at: s.flatMap(anchor), d) }

    /// То же по точке (31.6в: подсказка времени). Точка — место приложения (так у новой формы: её место — `repeatHome`) — уже
    /// загруженный прогноз приложения: тот же прогноз, а ждать прогноз точки значило бы открыть форму без плашки погоды наверху.
    func formDay(at p: GeoPoint?, _ d: CivilDate) -> WeatherDay? {
        guard let p, !sameAsAppPlace(p) else { return light.weather.day(for: d) }
        return pointDay(p, d)?.day
    }

    /// Точка — место приложения (тот же ключ прогноза, ~100 м).
    func sameAsAppPlace(_ p: GeoPoint) -> Bool { PointWeather.key(cardPlace(p)) == PointWeather.key(place.place) }

    /// Якорь места съёмки формы (`anchor` её записи); места нет — `nil`.
    func formAnchor(_ f: EventForm) -> GeoPoint? { formSession(f).flatMap(anchor) }

    /// Спросить прогноз места съёмки открытой формы (31.6б) — как карточка спрашивает свой (`askCardWeather`): форме он нужен
    /// для пожеланий. Место у формы тоже меняется, поэтому спрашивается при каждой правке; уже спрошенное место не спрашивается.
    func askFormWeather() {
        guard let f = form, f.mode != .meet, let s = formSession(f), let a = anchor(s), forecastReaches(s.day) else { return }
        pointWeather.ask(cardPlace(a))
    }

    /// Утренняя ли съёмка формы (31.6): правило карточки `shootsAtDawn` на ещё не сохранённой записи — форма и карточка судят
    /// пожелания одним небом.
    func formShootsAtDawn(_ f: EventForm) -> Bool {
        formSession(f).map(shootsAtDawn) ?? false
    }

    /// Луна во время съёмки из формы (30г.12, вариант А): ответ строки «Луна» карточки на ещё не сохранённую запись,
    /// плюс «ночь ли» в точке, где луна на небе. Только при пожелании «Луна»: другим пожеланиям он не нужен.
    func shootMoon(_ f: EventForm) -> ShootMoon? {
        guard f.wishes.contains(.moon) else { return nil }
        let s = f.session(orgName: nil, and: "", studios: snapshot.studios, spots: snapshot.spots,
                          homeCity: homeCityName, now: now())
        return ShootMoon.make(moonAnswer(s)) { p in self.sunAltitude(s, at: p?.minute ?? s.start) }
    }

    /// «Замысел против прогноза» (веб `wishesCheck`): первое несбывшееся пожелание
    /// словами — заголовок и текст. У встречи пожеланий нет. «Звёзды» называют все причины сразу, как карточка (30г.11).
    public func formWishWarning(_ f: EventForm) -> WishWarning? {
        guard f.mode != .meet,
              // Без «Луны» (30г.6) и «Звёзд» (30г.7, опись № 203) о них плашка молчит: скрытое пожелание остаётся в форме,
              // но не проверяется.
              let c = WishCheck.first(shownWishes(f.wishes), sky: wishSky(f.day, form: f), city: f.sessionPlace.isCity) else { return nil }
        // «Луна» (30г.12): луны в съёмку нет — слова строки карточки, заголовок свой.
        if let n = c.moon { return WishWarning(title: lexicon.t("wc.moonAwayT"), message: moonWords(n)) }
        // «Звёзды» (30г.11): все причины словами строки карточки — заголовок «Млечного Пути не будет видно», текст — причины.
        if !c.stars.isEmpty {
            let w = noStarsWords(c.stars)
            return WishWarning(title: w.head, message: w.why)
        }
        var params = c.params
        if let q = c.sky { params["sky"] = lexicon.t("qualSky." + q.rawValue).lowercased() }
        if let w = c.wish { params["wish"] = lexicon.t("wish." + w.rawValue).lowercased() }
        return WishWarning(title: lexicon.t("wc." + c.key + "T"), message: lexicon.t("wc." + c.key + "M", params))
    }

    private func formEdit(_ change: (inout EventForm) -> Void) {
        guard var f = form else { return }
        change(&f)
        form = f
        formChanged()
    }
}
