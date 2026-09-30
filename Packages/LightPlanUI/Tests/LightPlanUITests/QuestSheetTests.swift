import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Итерация 28, шаг 9: опросник на карточке — знак QR, отметка «отправлен», вставка и ссылка своей схемы,
/// наложение ответа на форму записи, черновик при повторном открытии (справка `docs/quest_reference.md`).
@MainActor
struct QuestSheetTests {

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
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    /// Встреча «свадьба» с именем невесты «Лена» и пустым женихом.
    private func model() -> AppModel {
        var s = Session(id: "wm1", kind: .meet, day: CivilDate(year: 2026, month: 9, day: 22), start: 840, end: 900,
                        duration: 60, genre: .wedding)
        s.persons = [Person(name: "Лена", phone: ""), Person(name: "", phone: "")]
        var snap = Snapshot()
        snap.sessions = [s]
        snap.practice = "ru"
        let now = ISO8601DateFormatter().date(from: "2026-09-22T12:00:00+03:00")!
        let app = AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                           locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                           weatherSource: NoWeather(), now: { now })
        app.draftStore = MemoryDraftStore()          // черновик формы не должен пережить тест в UserDefaults
        return app
    }

    /// Код, как его собирает страница: JSON → UTF-8 → base64url без «=».
    private func code(_ obj: [String: String]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func rec(_ app: AppModel) -> Session { app.sessions.first { $0.id == "wm1" }! }

    // MARK: - Знак

    @Test func battleLinkDrawsFortyOneModulesWithFinderCorner() throws {
        let m = try #require(QuestQR.matrix(QuestFlow.link(recordId: "k3f9a0x1zq")))
        #expect(m.count == 41 && m.allSatisfy { $0.count == 41 }, "\(m.count)")        // справка: 88 знаков → версия 6 → 41×41
        #expect((0..<7).allSatisfy { m[0][$0] && m[$0][0] })              // угловой знак: сплошная кромка 7 модулей
        #expect(!m[0][7] && !m[7][0])                                     // и светлый зазор после него
    }

    // MARK: - Лист

    @Test func openingSheetShowsSignAndMarksSentOnce() {
        let app = model()
        #expect(rec(app).questSent == nil)
        app.openQuest(for: rec(app))
        #expect(app.quest.isOpen && app.quest.recordId == "wm1")
        let first = rec(app).questSent
        #expect(first != nil)
        #expect(app.questURL()?.absoluteString.hasSuffix("?c=beta&r=wm1") == true)
        app.closeQuest()
        #expect(!app.quest.isOpen)
        app.openQuest(for: rec(app))
        #expect(rec(app).questSent == first)                              // повторный показ дату не двигает
    }

    @Test func copyFallbackMarksSentAndSaysSo() {
        let app = model()
        app.openQuest(for: rec(app))
        app.copyQuestLink()
        #expect(app.quest.copied)
    }

    @Test func crossHidesRowAndToggleBringsItBack() {
        let app = model()
        let phase = app.phase(of: rec(app))
        #expect(app.questRowShown(rec(app), phase: phase))
        app.setQuestOff(true, for: rec(app))
        #expect(!app.questRowShown(rec(app), phase: phase))
        app.setQuestOff(false, for: rec(app))
        #expect(app.questRowShown(rec(app), phase: phase))
    }

    // MARK: - Вставка

    @Test func pasteFillsEmptyFieldsKeepsFilledOnesAndNotesClash() {
        let app = model()
        app.openQuest(for: rec(app))
        let c = code(["b": "Елена", "g": "Слава", "d": "2027-06-15"])
        app.quest.paste = "Вот ответ: https://x.y/beta/?ans=\(c)&r=wm1 спасибо"
        #expect(app.applyPastedQuest() == .applied(clash: 1))
        #expect(!app.quest.isOpen)                                        // лист закрылся, открылась форма
        let f = app.form!
        #expect(f.persons[0].name == "Лена" && f.persons[1].name == "Слава")   // занятое не тронуто, пустое заполнено
        #expect(f.notes.contains("Дата свадьбы: 15 июня 2027"))
        #expect(f.notes.contains("Невеста: Лена / Елена"))                // расхождение — словами в заметке
        #expect(app.formNote?.hasPrefix("Заполнено по ответам клиента") == true)
        #expect(rec(app).persons[1].name == "")                           // запись не сохранена: это черновик формы
    }

    @Test func pasteWithoutAnswerOrWithBrokenCodeSaysSoAndOpensNothing() {
        let app = model()
        app.openQuest(for: rec(app))
        app.quest.paste = "просто текст"
        #expect(app.applyPastedQuest() == .noAnswer)
        #expect(app.quest.message == app.lexicon.t("quest.pasteBad") && app.quest.isOpen && app.form == nil)
        app.quest.paste = "?ans=!!!"
        #expect(app.applyPastedQuest() == .noAnswer)                      // не base64url — регулярка ответа не находит
        app.quest.paste = "?ans=" + code(["zzz": "x"])
        #expect(app.applyPastedQuest() == .bad)
        #expect(app.quest.message == app.lexicon.t("quest.badTitle") && app.form == nil)
    }

    @Test func longAnswerIsCutAndSaidSo() {
        let app = model()
        app.openQuest(for: rec(app))
        app.quest.paste = "?ans=" + code(["w": String(repeating: "я", count: 601)])
        _ = app.applyPastedQuest()
        #expect(app.formNote?.contains("обрезан до 600") == true)         // веб терял хвост молча (ошибка А5)
        #expect(app.form!.notes.contains(String(repeating: "я", count: 600)))
    }

    // MARK: - Ссылка своей схемы

    @Test func appSchemeLinkFindsRecordByItsSign() {
        let app = model()
        let url = URL(string: "lightplan://quest?ans=\(code(["g": "Слава"]))&r=wm1")!
        #expect(app.openQuestLink(url) == .applied(clash: 0))
        #expect(app.form?.id == "wm1" && app.form?.persons[1].name == "Слава")
    }

    @Test func foreignLinkIsLeftAlone() {
        let app = model()
        #expect(app.openQuestLink(URL(string: "https://example.com/?ans=\(code(["g": "Слава"]))")!) == nil)
        #expect(app.form == nil)
    }

    @Test func answerWithoutKnownRecordOpensNewWeddingMeeting() {
        let app = model()
        #expect(app.openQuestLink(URL(string: "lightplan://quest?ans=\(code(["b": "Катя", "g": "Слава"]))&r=nosuch")!) == .applied(clash: 0))
        let f = app.form!
        #expect(f.isNew && f.mode == .meet && f.genre == .wedding)
        #expect(f.persons[0].name == "Катя" && f.persons[1].name == "Слава")
    }

    // MARK: - Открытая форма (ревью GPT к fde8c6c)

    @Test func linkDoesNotReplaceOpenFormOfAnotherRecord() {
        let app = model()
        app.openForm(day: CivilDate(year: 2026, month: 9, day: 25), start: 600, fromLight: false, mode: .shoot)
        app.form!.notes = "набрано руками"
        let id = app.form!.id
        let url = URL(string: "lightplan://quest?ans=\(code(["g": "Слава"]))&r=wm1")!
        #expect(app.openQuestLink(url) == .held)
        #expect(app.form?.id == id && app.form?.notes == "набрано руками")   // несохранённое цело
        app.closeForm()
        app.openForm(editing: "wm1")                                         // ответ ждал в черновике
        #expect(app.form!.persons[1].name == "Слава")
    }

    @Test func linkForTheSameOpenRecordLaysOntoIt() {
        let app = model()
        app.openForm(editing: "wm1")
        app.form!.notes = "мои заметки"
        let url = URL(string: "lightplan://quest?ans=\(code(["g": "Слава"]))&r=wm1")!
        #expect(app.openQuestLink(url) == .applied(clash: 0))
        #expect(app.form!.persons[1].name == "Слава" && app.form!.notes == "мои заметки")
    }

    // MARK: - Черновик

    @Test func closedFormKeepsAnswerAndReopenDoesNotDuplicateNotes() {
        let app = model()
        app.quest.recordId = "wm1"
        let c = code(["w": "Без цветов", "g": "Слава"])
        _ = app.receiveQuest("?ans=\(c)&r=wm1", into: nil)
        app.closeForm()                                                   // закрыли, не сохранив
        #expect(app.questDrafts.pending(for: "wm1")?.code == c)           // ответ не пропал вместе с формой (ошибка А3)
        app.openForm(editing: "wm1")
        #expect(app.form!.persons[1].name == "Слава")
        app.reapplyQuestDraft(for: "wm1")                                 // повторное наложение — заметка не двоится
        #expect(app.form!.notes.components(separatedBy: "Без цветов").count == 2)
        _ = app.saveForm()
        #expect(app.questDrafts.pending(for: "wm1") == nil)               // сохранили — черновик не нужен
        #expect(rec(app).persons[1].name == "Слава")
    }
}
