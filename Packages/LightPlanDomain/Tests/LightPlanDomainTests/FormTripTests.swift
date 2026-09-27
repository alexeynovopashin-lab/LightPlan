import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Выезд, дорога и бронь в форме (итерация 24, шаг 4б).
@Suite struct FormTripTests {
    let day = CivilDate(year: 2026, month: 10, day: 10)
    let home = RepeatHome(town: "Томск", latitude: 56.48, longitude: 84.95)

    func fresh() -> EventForm {
        EventForm.new(id: "x1", day: day, start: 900, fromLight: false, genre: .portrait, light: nil, home: home)
    }

    @Test func cityNormIgnoresCaseYoAndPunctuation() {
        #expect(EventForm.cityNorm("Санкт-Петербург") == EventForm.cityNorm("санкт петербург"))
        #expect(EventForm.cityNorm("Королёв") == EventForm.cityNorm("королев"))
        #expect(EventForm.cityNorm("  ") == "")
    }

    @Test func tripFollowsCitiesUntilTouchedByHand() {
        var f = fresh()
        #expect(!f.trip(home: "Томск") && !f.tripRowShown(home: "Томск"), "город тот же — строки нет")
        f.setCity("Москва")
        #expect(f.trip(home: "Томск") && f.tripRowShown(home: "Томск"), "чужой город — выезд сам")
        #expect(!f.trip(home: ""), "родной город не знаем — молчим")
        f.setTrip(false)
        #expect(!f.trip(home: "Томск") && f.tripRowShown(home: "Томск"), "сняли руками — «успею», строка остаётся")
        f.setCity("томск")
        f.setTrip(true)
        #expect(f.trip(home: "Томск") && f.tripRowShown(home: "Томск"), "включили дома руками — строку не отбираем")
    }

    @Test func tripIsSavedWithPlaceAndSurvivesEditAndDraft() throws {
        var f = fresh()
        f.setCity("Москва")
        let s = f.session(orgName: nil, and: " и ", homeCity: "Томск")
        #expect(s.trip && !s.tripManual && s.tripPlace == "Москва")
        let back = EventForm.editing(s)
        #expect(back.tripManual && back.trip(home: "Томск"), "запись с выездом без отметки — правленая (веб L30416)")
        f.setTrip(false)
        let off = f.session(orgName: nil, and: " и ", homeCity: "Томск")
        #expect(!off.trip && off.tripManual && off.tripPlace.isEmpty)
        f.notes = "x"
        let data = try #require(f.draftData())
        let d = try #require(EventForm.fromDraft(data))
        #expect(d.tripManual && !d.tripOn)
    }

    @Test func meetingHasNoTrip() {
        var f = EventForm.new(id: "m", day: day, start: 900, fromLight: false, mode: .meet, genre: .portrait, light: nil, home: home)
        f.setCity("Москва")
        #expect(!f.tripRowShown(home: "Томск"))
        #expect(!f.session(orgName: nil, and: "", homeCity: "Томск").trip)
    }

    @Test func roadBlocksAreThoseWithinThreeDaysOrCoveringTheDay() {
        func b(_ id: String, _ k: BlockKind, _ d: Int, days: Int = 1, all: Bool = false) -> Block {
            var x = Block(id: id, kind: k, from: CivilDate(year: 2026, month: 10, day: d))
            x.allDay = all; x.days = days
            return x
        }
        let list = [b("far", .road, 1), b("off", .off, 9), b("fl", .flight, 7), b("rd", .road, 13),
                    b("long", .road, 2, days: 9, all: true), b("late", .road, 14)]
        #expect(EventForm.roadBlocks(near: day, in: list).map(\.id) == ["long", "fl", "rd"])
    }

    @Test func bookingLandsInTheHeadStudioStop() {
        var st = Studio(id: "st1", name: "Люмен", latitude: 56.47, longitude: 84.97)
        st.halls = [Studio.Hall(id: "h2", name: "Чёрный")]
        var f = fresh()
        f.route = [RoutePoint(start: 900, end: 960, name: "", placeText: "Люмен", studioId: "st1")]
        #expect(f.linkStudio(studios: [st]) == nil, "без ключа спрашивать некого")
        st.key = "k"
        #expect(f.linkStudio(studios: [st])?.id == "st1")
        f.applyBooking(ref: "B7", hallId: "h2", start: 910, end: 1000, label: { "\($0), зал \($1)" }, spots: [], studios: [st])
        #expect(f.bookingRef == "B7" && f.route[0].hallId == "h2" && f.route[0].placeText == "Люмен, зал Чёрный")
        #expect(f.route[0].start == 910 && f.route[0].end == 1000)
        let s = f.session(orgName: nil, and: "", studios: [st])
        #expect(s.bookingRef == "B7" && s.hallId == "h2" && s.rentFrom == 910)
        f.route = []
        #expect(f.session(orgName: nil, and: "", studios: [st]).bookingRef == nil, "студии нет — брони нет")
    }
}
