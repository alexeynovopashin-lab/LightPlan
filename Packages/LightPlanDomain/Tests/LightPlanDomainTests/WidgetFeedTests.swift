import Testing
import Foundation
@testable import LightPlanDomain
import LightPlanCore

/// Шаг 30б.1: файл, что приложение оставляет виджету, и заглушка «☀︎ начало золотого часа» по нему.
struct WidgetFeedTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Виджет и приложение находят одну папку: у расширения адрес приложения + `.Widget`.
    @Test func groupIsTheAppsForBothProcesses() {
        #expect(WidgetFeed.groupID(bundleID: "Novopashin.LightPlan") == "group.Novopashin.LightPlan")
        #expect(WidgetFeed.groupID(bundleID: "Novopashin.LightPlan.Widget") == "group.Novopashin.LightPlan")
        #expect(WidgetFeed.groupID(bundleID: "Novopashin.LightPlan.slotC.Widget") == "group.Novopashin.LightPlan.slotC")
    }

    @Test func roundTripAndForeignFile() {
        let feed = WidgetFeed(place: tomsk)
        #expect(WidgetFeed.decode(feed.encoded()) == feed)
        #expect(WidgetFeed.decode(Data("{\"nope\":1}".utf8)) == nil)
        #expect(WidgetFeed.decode(Data()) == nil)
    }

    /// Начало золотого часа — то же число, что `SolarDay` экранов, переведённое в момент по зоне места.
    /// Томск 24.10.2026: замер спайка 17:02:48 (+7); здесь — то же с точностью до минут разницы `.web`/`.iau`.
    @Test func goldenStartIsTheScreensNumberAsAMoment() throws {
        let day = CivilDate(year: 2026, month: 10, day: 24)
        let start = try #require(tomsk.goldenStart(on: day))
        let place = try #require(tomsk.place)
        let minutes = try #require(SolarDay(date: day, place: place).goldenB)
        #expect(abs(start.timeIntervalSince(utc(2026, 10, 24, 0)) - (minutes - 7 * 60) * 60) < 0.001)
        let gap = start.timeIntervalSince(utc(2026, 10, 24, 10, 2).addingTimeInterval(48))
        #expect(abs(gap) < 180, "Томск 24.10: \(start), спайк 10:02:48 UTC")
    }

    /// «Сегодня» — по часам места: в 20:00 UTC 24.10 в Томске уже 25-е.
    @Test func todayIsThePlacesDay() {
        #expect(tomsk.today(at: utc(2026, 10, 24, 16, 59)) == CivilDate(year: 2026, month: 10, day: 24))
        #expect(tomsk.today(at: utc(2026, 10, 24, 20, 0)) == CivilDate(year: 2026, month: 10, day: 25))
    }

    /// Запасная зона без сети (`fixed:<секунды>`) читается так же, как имя IANA.
    @Test func fixedZoneWorks() throws {
        let fixed = WidgetFeed.Spot(name: "", latitude: tomsk.latitude, longitude: tomsk.longitude, zone: "fixed:25200")
        let day = CivilDate(year: 2026, month: 10, day: 24)
        #expect(fixed.timeZone?.secondsFromGMT() == 25200)
        #expect(fixed.goldenStart(on: day) == tomsk.goldenStart(on: day))
        #expect(WidgetFeed.Spot(name: "", latitude: 0, longitude: 0, zone: "Nowhere/Void").place == nil)
    }

    /// Полярная ночь: солнце до 6° не поднимается — начала золотого часа нет, плашка покажет прочерк.
    @Test func polarNightHasNoGoldenStart() {
        let tromso = WidgetFeed.Spot(name: "Tromsø", latitude: 69.6496, longitude: 18.956, zone: "Europe/Oslo")
        #expect(tromso.goldenStart(on: CivilDate(year: 2026, month: 12, day: 20)) == nil)
    }
}
