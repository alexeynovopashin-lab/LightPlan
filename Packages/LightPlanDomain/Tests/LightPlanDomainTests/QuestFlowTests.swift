import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Опросник на карточке: условия строки, адрес страницы, отметка «отправлен», своя схема (итерация 28, шаг 9).
@Suite struct QuestFlowTests {
    static let day = CivilDate(year: 2026, month: 9, day: 22)

    static func rec(_ kind: RecordKind, genre: Genre? = .wedding) -> Session {
        var s = Session(id: "abc123", kind: kind, day: day, start: 600)
        s.genre = genre
        return s
    }

    @Test func rowFitsWeddingMeetUntilGrown() {
        var m = Self.rec(.meet)
        #expect(QuestFlow.fits(m, phase: .before))
        #expect(QuestFlow.fits(m, phase: .after))          // встреча — «пока не отработана», фаза не важна
        m.grewOn = Self.day
        #expect(!QuestFlow.fits(m, phase: .before))
    }

    @Test func rowFitsWeddingShootOnlyBefore() {
        let s = Self.rec(.shoot)
        #expect(QuestFlow.fits(s, phase: .before))
        #expect(!QuestFlow.fits(s, phase: .during))
        #expect(!QuestFlow.fits(s, phase: .after))
    }

    @Test func otherGenresHaveNoRow() {
        #expect(!QuestFlow.fits(Self.rec(.shoot, genre: .portrait), phase: .before))
        #expect(!QuestFlow.fits(Self.rec(.meet, genre: nil), phase: .before))
    }

    @Test func crossHidesRowButNotFit() {
        var s = Self.rec(.meet)
        s.questOff = true
        #expect(QuestFlow.fits(s, phase: .before))         // в режиме перестановки строка нужна, чтобы вернуть
        #expect(!QuestFlow.rowShown(s, phase: .before))
    }

    @Test func linkCarriesChannelAndRecord() {
        #expect(QuestFlow.link(recordId: "k3f9a0x1zq")
                == "https://alexeynovopashin-lab.github.io/Light-Plan/quest/wedding.html?c=beta&r=k3f9a0x1zq")
        #expect(QuestFlow.link(recordId: "k3f9a0x1zq").count == 88)   // справка: боевой адрес 88 знаков
    }

    @Test func linkDropsRecordWhenPageWouldRejectIt() {
        let bare = "https://alexeynovopashin-lab.github.io/Light-Plan/quest/wedding.html?c=beta"
        #expect(QuestFlow.link(recordId: nil) == bare)
        #expect(QuestFlow.link(recordId: "") == bare)
        #expect(QuestFlow.link(recordId: "sd_sep_meet") == bare)      // «_» страница не пропускает
        #expect(QuestFlow.link(recordId: "ABC") == bare)
        #expect(QuestFlow.link(recordId: String(repeating: "a", count: 33)) == bare)
    }

    @Test func markSentOnceOnly() {
        var s = Self.rec(.meet)
        let first = Date(timeIntervalSince1970: 1_000)
        #expect(QuestFlow.markSent(&s, at: first, nowMs: 5))
        #expect(s.questSent == first && s.modifiedAt == 5)
        #expect(!QuestFlow.markSent(&s, at: Date(timeIntervalSince1970: 9_000), nowMs: 9))
        #expect(s.questSent == first && s.modifiedAt == 5)
    }

    @Test func appSchemeLinkYieldsAnswer() {
        let code = "eyJiIjoi0JXQu9C10L3QsCJ9"    // {"b":"Елена"}
        let url = URL(string: "LightPlan://quest?ans=\(code)&r=abc123")!
        #expect(QuestFlow.isAppLink(url))
        #expect(!QuestFlow.isAppLink(URL(string: "https://example.com/?ans=\(code)")!))
        guard case .answer(let a, let id) = QuestParse.receive(url.absoluteString) else { Issue.record("нет ответа"); return }
        #expect(a["b"] == "Елена" && id == "abc123")
    }
}
