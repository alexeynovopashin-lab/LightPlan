import Testing
import LightPlanCore
import LightPlanDomain
@testable import LightPlanUI

/// Правила видов «Съёмок», которых пара снимков не ловит: имя клиента в
/// редких записях и порог подписи часа под капсулой «сейчас».
@Suite struct PlannerViewsTests {
    private let day = CivilDate(year: 2026, month: 9, day: 23)

    private func shoot(_ edit: (inout Session) -> Void) -> Session {
        var s = Session(id: "s", day: day, start: 600, duration: 60, genre: .portrait)
        edit(&s)
        return s
    }

    @Test func clientNameOrder() {
        let org = Org(id: "o", name: "Ресторан «Соль»")
        let w = PlannerWords(lexicon: Lexicon("ru"), orgs: [org])
        // Пара — по именам без фамилий, через «и» словаря.
        let pair = shoot { $0.persons = [Person(name: "Аня Ковалёва", phone: ""), Person(name: "Марк", phone: "")] }
        #expect(w.clientName(pair) == "Аня" + Lexicon("ru").t("card.and") + "Марк")
        // Без пары — организация.
        #expect(w.clientName(shoot { $0.orgId = "o"; $0.contact = "Ира" }) == "Ресторан «Соль»")
        // Строка клиента без номера, который в неё вписан.
        #expect(w.clientName(shoot { $0.contact = "Сергей Плахов · +7 913 555-66-77" }) == "Сергей Плахов")
        #expect(w.clientName(shoot { $0.contact = "" }) == "")
    }

    @Test func firstPhonePrefersPairThenFields() {
        let w = PlannerWords(lexicon: Lexicon("ru"), orgs: [])
        #expect(w.firstPhone(shoot { $0.persons = [Person(name: "А", phone: ""), Person(name: "Б", phone: "+7 1")]
            $0.clientPhone = "+7 2" }) == "+7 1")
        #expect(w.firstPhone(shoot { $0.clientPhone = "+7 2" }) == "+7 2")
        #expect(w.firstPhone(shoot { $0.notes = "звонить +7 (913) 555-66-77 вечером" }) == "+7 (913) 555-66-77")
    }

    /// 10:00 гаснет на 09:41 и держится погашенной до 10:24 (веб: капсула
    /// достаёт цифры за 12,2 pt до черты и отпускает через 15,7).
    @Test func hourLabelHidesUnderNowCapsule() {
        #expect(!PlannerDayBody.hushed(10, now: 9 * 60 + 40))
        #expect(PlannerDayBody.hushed(10, now: 9 * 60 + 41))
        #expect(PlannerDayBody.hushed(10, now: 10 * 60 + 24))
        #expect(!PlannerDayBody.hushed(10, now: 10 * 60 + 25))
    }
}
