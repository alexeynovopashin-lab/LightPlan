import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// Итерация 24, шаг 4б: выезд и дорога, связь с бронью, поиск города,
/// наложения в плашке, студия из листа «Где снимаем».
@MainActor
struct FormTripFlowTests {

    private struct NoWeather: WeatherSource {
        struct Offline: Error {}
        func fetchHourly(at place: Place) async throws -> HourlyWeather { throw Offline() }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { throw Offline() }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct Cities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] {
            query == "Новосибирск" ? [CityHit(name: "Новосибирск", area: "", countryCode: "ru",
                                              coordinate: GeoCoordinate(latitude: 55.03, longitude: 82.92))] : []
        }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }
    private final class Studio1: BookingMatching, @unchecked Sendable {
        var asked: [BookingQuery] = []
        var answer: BookingAnswer?
        var fail = false
        func match(_ q: BookingQuery) async throws -> BookingAnswer? {
            asked.append(q)
            if fail { throw URLError(.timedOut) }
            return answer
        }
    }

    let day = CivilDate(year: 2026, month: 10, day: 10)

    private func model(_ snap: Snapshot = Snapshot()) -> AppModel {
        var s = snap
        s.extra["me"] = .object(["city": .string("Томск"), "phone": .string("+7 913 111-22-33")])
        let app = AppModel(snapshot: s, store: nil, language: "ru", zone: TimeZone(identifier: "Asia/Tomsk")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: Cities(), weatherSource: NoWeather())
        app.draftStore = MemoryDraftStore()
        return app
    }

    private var lumen: Studio {
        var st = Studio(id: "st1", name: "Люмен", latitude: 56.47, longitude: 84.97)
        st.town = "Томск"; st.key = "k1"
        st.halls = [Studio.Hall(id: "h1", name: "Белый")]
        return st
    }

    @Test func tripOnWithoutRoadOpensRoadSheetOverTheForm() throws {
        let app = model()
        #expect(app.homeCityName == "Томск")
        app.openForm(day: day)
        app.setFormCity("Москва")
        let f = try #require(app.form)
        #expect(f.trip(home: app.homeCityName))
        #expect(app.formRoadRow(f).set == false)
        app.setFormTrip(true)
        let b = try #require(app.blockSheet?.block)
        #expect(b.kind == .road && b.note == "Москва" && b.start == 540 && b.from == day && !b.allDay)
        let s = try #require(app.saveForm())
        #expect(s.trip && s.tripManual && s.tripPlace == "Москва")
    }

    @Test func roadRowNamesTheBlocksNearby() throws {
        var snap = Snapshot()
        var b = Block(id: "b1", kind: .flight, from: CivilDate(year: 2026, month: 10, day: 8))
        b.start = 540; b.duration = 240
        snap.blocks = [b]
        let app = model(snap)
        app.openForm(day: day)
        app.setFormCity("Москва")
        let f = try #require(app.form)
        let r = app.formRoadRow(f)
        #expect(r.set && r.value.contains(app.lexicon.t("blkKind.flight")))
        app.openRoadSheet()
        #expect(app.blockSheet?.block.id == "b1", "дорога рядом есть — она на правку")
    }

    @Test func typedCityMovesThePointUntilAPlaceIsChosen() async throws {
        let app = model()
        app.openForm(day: day)
        app.setFormCity("новосибирск")
        await app.commitFormCity()
        let f = try #require(app.form)
        #expect(f.sessionPlace.town == "Новосибирск", "первая буква — заглавная")
        #expect(f.sessionPlace.latitude == 55.03 && f.sessionPlace.longitude == 82.92)
    }

    @Test func overlapBeatsWeatherInThePlaque() throws {
        var snap = Snapshot()
        var other = Session(id: "o1", kind: .shoot, day: day, start: 870)
        other.duration = 90; other.end = 960; other.contact = "Катя"; other.genre = .portrait
        snap.sessions = [other]
        let app = model(snap)
        app.openForm(day: day, start: 900, fromLight: false)
        let f = try #require(app.form)
        let w = try #require(app.formWarning(f))
        #expect(w.title == app.lexicon.t("clash.overlapT"))
        #expect(w.message.contains("Катя"))
    }

    @Test func linkAsksTheHeadStudioAndTakesItsHallAndHours() async throws {
        var snap = Snapshot()
        snap.studios = [lumen]
        let app = model(snap)
        let gate = Studio1()
        app.bookingMatch = gate
        app.openForm(day: day, start: 900, fromLight: false)
        app.addFormStop()
        app.setFormStopStudio(0, studio: lumen)
        app.setFormStopTime(0, end: false, minute: 900)
        app.setFormStopTime(0, end: true, minute: 1020)
        let f = try #require(app.form)
        #expect(app.formLinkShown(f))
        #expect(await app.linkFormBooking() == "form.linkNone")
        gate.answer = BookingAnswer(ref: "B9", hallId: "h1", start: "15:10", end: "17:00")
        #expect(await app.linkFormBooking() == "form.linked")
        let q = try #require(gate.asked.last)
        #expect(q.date == "2026-10-10" && q.from == "15:00" && q.to == "17:00" && q.studioKey == "k1")
        #expect(q.phones == ["79131112233"])
        let r = try #require(app.form?.route.first)
        #expect(r.hallId == "h1" && r.start == 910 && r.end == 1020 && app.form?.bookingRef == "B9")
        gate.fail = true
        #expect(await app.linkFormBooking() == "form.linkOff")
        #expect(app.form?.bookingRef == nil)
    }

    @Test func studioCardSavesFirstWithoutEmptyHalls() throws {
        var snap = Snapshot()
        snap.studios = [lumen]
        let app = model(snap)
        app.openForm(day: day)
        app.form?.sessionPlace = FormPlace(town: "Томск", latitude: 56.48, longitude: 84.95)
        var d = StudioDraft(new: "Томск", at: GeoCoordinate(latitude: 56.49, longitude: 84.95))
        d.name = "  Маяк "; d.address = "Ленина, 1"; d.phone = "+7 913 000-00-00"
        d.halls = [.init(id: "a", name: "Лофт"), .init(id: "b", name: "  ")]
        let st = app.saveStudio(d)
        #expect(app.studios.first?.id == st.id && app.studios.count == 2)
        #expect(st.name == "Маяк" && st.halls.map(\.name) == ["Лофт"] && st.town == "Томск")
        var e = StudioDraft(lumen, fallback: app.place.coordinate)
        e.name = "Люмен 2"; e.town = ""
        let again = app.saveStudio(e)
        #expect(again.id == "st1" && app.studios[1].name == "Люмен 2" && app.studios.count == 2, "прежняя правится на месте")
        #expect(again.key == "k1", "ключ брони не теряется при правке")
        // Далеко от места формы — город не наследуется.
        var far = StudioDraft(new: "", at: GeoCoordinate(latitude: 55.75, longitude: 37.62))
        far.name = "Москва-студия"
        #expect(app.saveStudio(far).town.isEmpty)
    }

    @Test func lostStudiosComeFromRecords() {
        var snap = Snapshot()
        var s = Session(id: "o1", kind: .shoot, day: day, start: 600)
        s.studioId = "gone"; s.place = "Старая"; s.placeTown = "Томск"
        snap.sessions = [s]
        let app = model(snap)
        #expect(app.lostStudios.map(\.id) == ["gone"] && app.lostStudios.first?.name == "Старая")
    }
}
