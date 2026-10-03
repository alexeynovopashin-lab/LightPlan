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
    func openStopPlace(_ i: Int, way: PlaceSheetForm.Way) {
        placeSheetStart = way
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

    public func toggleFormWish(_ w: Wish) { formEdit { $0.toggle(wish: w) } }

    /// Небо дня для проверки пожеланий — у места приложения, как у веба
    /// (`qualityOf`, `dayWeather`, `computeSun` смотрят на `LAT`/`LON`).
    func wishSky(_ day: CivilDate) -> WishSky {
        let wx = light.weather.day(for: day)      // `nil` — прогноза нет: пожелания про погоду молчат
        let p = place.place
        let sun = SolarDay(date: day, place: p)
        let moon = MoonVsStars(date: day, place: p)
        return WishSky(quality: wx?.quality, sunsetScore: wx?.sunset, astroNight: sun.astroB != nil,
                       moonLevel: moon.level?.rawValue, moonPercent: moon.percent,
                       moonFraction: MoonPhase(date: day, minutes: 1320, zone: p.zone).fraction)
    }

    /// «Замысел против прогноза» (веб `wishesCheck`): первое несбывшееся пожелание
    /// словами — заголовок и текст. У встречи пожеланий нет.
    public func formWishWarning(_ f: EventForm) -> WishWarning? {
        guard f.mode != .meet,
              let c = WishCheck.first(f.wishes, sky: wishSky(f.day), city: f.sessionPlace.isCity) else { return nil }
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
