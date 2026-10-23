import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Правило «долг» стопки долгов (шаг К5, `clients_reference.md` § 7.2): каждое условие по отдельности — работа, жанр
/// со сдачей или без жанра, съёмка позади, «сдана» не нажата; срок сдачи статус не меняет; порядок — старые первыми.
@Suite struct DebtsTests {
    static let oct20 = CivilDate(year: 2026, month: 10, day: 20)
    /// 23.10, 12:00 по часам места.
    static let now = WallTime(day: CivilDate(year: 2026, month: 10, day: 23), minutes: 720)

    static func shoot(_ id: String = "s", day: CivilDate = oct20, start: Int = 600, dur: Int = 120,
                      kind: RecordKind = .shoot, genre: Genre? = .portrait) -> Session {
        Session(id: id, kind: kind, day: day, start: start, duration: dur, genre: genre)
    }

    static func debt(_ s: Session, at now: WallTime = now, manualEnd: Bool = false) -> Bool {
        Debts.isDebt(s, now: now, manualEnd: manualEnd)
    }

    @Test func pastUndeliveredShootIsADebt() {
        #expect(Self.debt(Self.shoot()))
    }

    @Test func deliveredByHandIsNotADebt() {
        var s = Self.shoot()
        s.delivered = true
        #expect(!Self.debt(s))
    }

    @Test func onlyWorkIsADebt() {
        #expect(!Self.debt(Self.shoot(kind: .meet)), "встреча не сдаётся")
        #expect(!Self.debt(Self.shoot(kind: .event)), "чужое событие не сдаётся")
    }

    @Test func genreWithoutDeliveryIsNotADebtNoGenreIs() {
        #expect(!Self.debt(Self.shoot(genre: .landscape)), "пейзаж — без сдачи")
        #expect(!Self.debt(Self.shoot(genre: .street)), "стрит — без сдачи")
        #expect(Self.debt(Self.shoot(genre: nil)), "без жанра — долг (черновик из Календаря тоже)")
        #expect(Self.debt(Self.shoot(genre: .wedding)))
    }

    /// Съёмка позади — по фазе карточки на часах места: будущая, сегодняшняя до начала и идущая — не долг.
    @Test func onlyAShootThatIsOverIsADebt() {
        let today = Self.now.day
        #expect(!Self.debt(Self.shoot(day: today.adding(days: 3))), "впереди")
        #expect(!Self.debt(Self.shoot(day: today, start: 900)), "сегодня, ещё не начата")
        #expect(!Self.debt(Self.shoot(day: today, start: 660, dur: 120)), "идёт сейчас")
        #expect(Self.debt(Self.shoot(day: today, start: 540, dur: 120)), "сегодня, уже кончилась")
        // Свадьба через полночь со вчера: до 02:00 идёт, после — долг.
        let wed = Self.shoot(day: today.adding(days: -1), start: 1200, dur: 360)
        #expect(!Self.debt(wed, at: WallTime(day: today, minutes: 60)))
        #expect(Self.debt(wed, at: WallTime(day: today, minutes: 180)))
    }

    /// «Завершать вручную»: кончившаяся по рамкам, но не завершённая сегодня — ещё идёт; вчерашняя — позади.
    @Test func manualEndKeepsTodaysShootUntilFinished() {
        var s = Self.shoot(day: Self.now.day, start: 540, dur: 120)
        #expect(!Self.debt(s, manualEnd: true))
        s.doneAt = 650
        #expect(Self.debt(s, manualEnd: true))
        #expect(Self.debt(Self.shoot(), manualEnd: true))
    }

    /// Срок из карточки статус не меняет: без срока, в срок и просроченная — одинаково долг.
    @Test func deadlineDoesNotChangeTheStatus() {
        for d in [DeadlineChoice.none, .days(90), .days(1), .auto] {
            var s = Self.shoot()
            s.deadline = d
            #expect(Self.debt(s), Comment(rawValue: "\(d)"))
        }
    }

    /// Порядок стопки: самый старый первым, в один день — раньше начало, при равном — раньше записана.
    @Test func stackIsOldestFirst() {
        let sessions = [
            Self.shoot("oct20_late", start: 900),
            Self.shoot("future", day: Self.now.day.adding(days: 2)),
            Self.shoot("oct02", day: CivilDate(year: 2026, month: 10, day: 2)),
            Self.shoot("meet", kind: .meet),
            Self.shoot("oct20_a", start: 600),
            Self.shoot("oct20_b", start: 600),
            { var s = Self.shoot("done", day: CivilDate(year: 2026, month: 9, day: 1)); s.delivered = true; return s }(),
            Self.shoot("land", genre: .landscape),
        ]
        let ids = Debts.stack(sessions, now: { _ in Self.now }, manualEnd: false).map(\.id)
        #expect(ids == ["oct02", "oct20_a", "oct20_b", "oct20_late"])
    }
}
