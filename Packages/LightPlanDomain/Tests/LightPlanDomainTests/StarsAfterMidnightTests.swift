import Foundation
import Testing
import LightPlanCore
@testable import LightPlanDomain

/// 31.8, п. 1 (Алексей 19.11 «А, с подсветкой»): в день, когда ночь тёмная только после полуночи, форма ставит «Звёздам» следующую
/// дату и время по тому же правилу, что в другие дни; дата подсвечена, как время при сдвиге (30д). Ночь D — вечер D + утро D+1.
@Suite struct StarsAfterMidnightTests {
    static func place(_ lat: Double, _ lon: Double, _ zone: String) -> Place { Place(latitude: lat, longitude: lon, zone: ZoneID(zone)!) }
    static let kyiv = place(50.45, 30.52, "Europe/Kiev"), tomsk = place(56.49, 84.95, "Asia/Tomsk")
    let d = CivilDate(year: 2027, month: 5, day: 27)
    /// Окно ночи 27.05 на шкале 27.05: 00:33–01:17 уже 28-го.
    let late = LightGoal(wish: .stars, event: 1473, from: 1473, to: 1517, darkUntil: 87)

    func facts(_ f: EventForm, start: Int = 720) -> EventForm.TimeFacts {
        // Как в приложении: свет — ночи выбранной даты, окна — на шкалу дня формы.
        let lag = f.day.ordinal - f.lightDay.ordinal
        return EventForm.TimeFacts(goals: f.wishes.contains(.stars) ? [late.shifted(days: lag)] : [], defaultStart: start, step: 5) { _, _, _ in nil }
    }

    func form(duration: Int = 30) -> EventForm {
        var f = EventForm.new(id: "n", day: d, start: nil, fromLight: false, genre: .portrait, light: nil, step: 1)
        f.duration = duration
        return f
    }

    @Test("окно «Звёзд» по темноте после полуночи: Киев 27.05, Томск 29.04; обычный день и белая ночь — как до 31.8")
    func goalAfterMidnight() throws {
        for (p, day) in [(Self.kyiv, CivilDate(year: 2027, month: 5, day: 27)), (Self.tomsk, CivilDate(year: 2027, month: 4, day: 29))] {
            let sun = SolarDay(date: day, place: p), night = try #require(StarNightHours.dark(date: day, place: p))
            #expect(LightGoal.of(.stars, sun: sun) == nil, "без темноты ночи — как до 31.8")
            let g = try #require(LightGoal.of(.stars, sun: sun, night: night))
            #expect(g.from == Int(night.lowerBound.rounded()) && g.to == Int(night.upperBound.rounded()) && g.from >= 1440, "\(day): \(g)")
        }
        let winter = CivilDate(year: 2026, month: 12, day: 21), sun = SolarDay(date: winter, place: Self.tomsk)
        #expect(LightGoal.of(.stars, sun: sun, night: StarNightHours.dark(date: winter, place: Self.tomsk)) == LightGoal.of(.stars, sun: sun))
        let spb = Self.place(59.94, 30.31, "Europe/Moscow"), june = CivilDate(year: 2027, month: 6, day: 21)
        #expect(LightGoal.of(.stars, sun: SolarDay(date: june, place: spb), night: StarNightHours.dark(date: june, place: spb)) == nil)
    }

    @Test("предложенное время за полночью — следующая дата, дата и время подсвечены, ночь — выбранной даты")
    func proposalMovesToTheNextDate() {
        var f = form()
        f.wishes = [.stars]
        f.followProposal(facts(f))
        #expect(f.day == d.adding(days: 1) && f.start == 33, "\(f.day) \(f.start)")
        #expect(f.dateShifted && f.timeShifted && f.timeIsProposed && f.nightOf == d && f.lightDay == d)
        // Повторный пересчёт (смена жанра, закрытое колесо) не уводит дату дальше
        f.followProposal(facts(f))
        #expect(f.day == d.adding(days: 1) && f.start == 33 && f.nightOf == d)
    }

    @Test("съёмка длиннее темноты кончается вместе с ней — то же правило, что в другие дни")
    func longShootEndsWithTheDark() {
        var f = form(duration: 120)
        f.wishes = [.stars]
        f.followProposal(facts(f))
        #expect(f.day == d && f.start == 1517 - 120 && f.nightOf == nil, "начало ещё 27.05: \(f.day) \(f.start)")
        var g = form(duration: 60)
        g.wishes = [.stars]
        g.followProposal(facts(g))
        #expect(g.day == d.adding(days: 1) && g.start == 1517 - 60 - 1440 && g.dateShifted)
    }

    @Test("человек тронул время или дату — подсветка уходит; сняли «Звёзды» — форма возвращается на выбранную дату")
    func personTakesOver() {
        var a = form(); a.wishes = [.stars]; a.followProposal(facts(a))
        a.setStart(minute: 45)
        #expect(!a.dateShifted && a.day == d.adding(days: 1))
        var b = form(); b.wishes = [.stars]; b.followProposal(facts(b))
        b.setStart(day: d.adding(days: 3))
        #expect(!b.dateShifted && b.day == d.adding(days: 3))
        var c = form(); c.wishes = [.stars]; c.followProposal(facts(c))
        _ = c.toggleWish(.stars) { facts($0, start: 720) }
        #expect(c.day == d && c.start == 720 && !c.dateShifted, "\(c.day) \(c.start)")
    }

    @Test("черновик помнит выбранную дату: после перезапуска дата не уходит дальше")
    func draftKeepsTheChosenNight() throws {
        var f = form(); f.wishes = [.stars]; f.contact = "Оля"; f.followProposal(facts(f))
        let data = try #require(f.draftData())
        var back = try #require(EventForm.fromDraft(data))
        #expect(back.nightOf == d && back.day == d.adding(days: 1))
        back.followProposal(facts(back))
        #expect(back.day == d.adding(days: 1) && back.start == 33)
    }
}

/// 31.8, п. 2 «Б»: запись помнит, что время «Звёздам» поставило правило, — за те дату и начало, что в метке.
@Suite struct RuleNightRecordTests {
    func decode(_ json: String) throws -> Session { try JSONDecoder().decode(Session.self, from: Data(json.utf8)) }

    @Test("запись без метки (веб пересохранил) читается и судит часы съёмки; метка переживает запись-чтение")
    func recordWithAndWithoutTheMark() throws {
        let plain = try decode(#"{"id":"a","date":"2027-05-28","min":1,"wish":["stars"]}"#)
        #expect(plain.ruleNight == nil && plain.nightByRule == nil)
        let marked = try decode(#"{"id":"b","date":"2027-05-29","min":1,"wish":["stars"],"ruleNight":{"n":"2027-05-28","d":"2027-05-29","m":1}}"#)
        #expect(marked.nightByRule == CivilDate(year: 2027, month: 5, day: 28))
        let back = try decode(String(decoding: try JSONEncoder().encode(marked), as: UTF8.self))
        #expect(back.ruleNight == marked.ruleNight && back.extra["ruleNight"] == nil)
        let broken = try decode(#"{"id":"c","date":"2027-05-29","min":1,"ruleNight":{"n":"вчера"}}"#)
        #expect(broken.ruleNight == nil && broken.id == "c", "испорченная метка не роняет запись")
    }

    @Test("время или дату сдвинули (лента, Календарь, форма) — метка больше не ручается")
    func markVouchesOnlyForItsTime() throws {
        var s = try decode(#"{"id":"b","date":"2027-05-29","min":1,"ruleNight":{"n":"2027-05-28","d":"2027-05-29","m":1}}"#)
        s.start = 30
        #expect(s.nightByRule == nil)
        s.start = 1; s.day = CivilDate(year: 2027, month: 5, day: 30)
        #expect(s.nightByRule == nil)
    }

    @Test("форма пишет метку только за время правила и только со «Звёздами»; правка без касания времени её хранит")
    func formWritesTheMark() throws {
        let d = CivilDate(year: 2027, month: 5, day: 27)
        var f = EventForm.new(id: "n", day: d, start: nil, fromLight: false, genre: .portrait, light: nil, step: 1)
        f.wishes = [.stars]
        let s = f.session(orgName: nil, and: "", studios: [], spots: [], homeCity: "", now: Date())
        #expect(s.nightByRule == d)
        var plain = f; plain.wishes = [.sunset]
        #expect(plain.session(orgName: nil, and: "", studios: [], spots: [], homeCity: "", now: Date()).ruleNight == nil)
        var edit = EventForm.editing(s)
        #expect(edit.ruleNight == d && edit.session(orgName: nil, and: "", studios: [], spots: [], homeCity: "", now: Date()).nightByRule == d)
        edit.setStart(minute: s.start + 5)
        #expect(edit.ruleNight == nil && edit.session(orgName: nil, and: "", studios: [], spots: [], homeCity: "", now: Date()).ruleNight == nil)
    }
}
