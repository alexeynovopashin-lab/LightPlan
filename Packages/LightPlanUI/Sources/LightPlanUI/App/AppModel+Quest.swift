import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Опросник клиенту (итерация 28, шаг 9; справка `docs/quest_reference.md`)

/// Состояние листа опросника: чья запись, что вставлено, что сказано под полем. В запись не идёт.
struct QuestState: Equatable {
    /// Запись, для которой открыт лист; `nil` — лист закрыт.
    var recordId: String?
    var isOpen = false
    /// Вставленный текст.
    var paste = ""
    /// Строка под полем вставки: «в тексте нет ответа» и подобное (`quest.pasteBad`).
    var message: String?
    /// Ссылка ушла в буфер (запасной путь без системного листа): `quest.copiedTitle` под кнопкой.
    var copied = false
}

/// Чем кончилась попытка принять ответ клиента.
enum QuestOutcome: Equatable {
    /// Форма открыта с ответом; `clash` — сколько строк «не сходится».
    case applied(clash: Int)
    /// В тексте нет `ans=`.
    case noAnswer
    /// Код не читается (`quest.badTitle`).
    case bad
}

extension AppModel {

    // MARK: Строка карточки

    func questRowShown(_ s: Session, phase: EventPhase) -> Bool { QuestFlow.rowShown(s, phase: phase) }

    /// Крестик строки: опросник этой паре не нужен (веб `#cdQuestOff`). Возврат — тумблером в режиме перестановки.
    func setQuestOff(_ off: Bool, for s: Session) {
        guard let i = snapshot.sessions.firstIndex(where: { $0.id == s.id }), snapshot.sessions[i].questOff != off else { return }
        snapshot.sessions[i].questOff = off
        snapshot.sessions[i].modifiedAt = nowMs
        persist()
    }

    /// Слова строки: заголовок и подпись; отправленный опросник стихает (веб L30035–30041).
    func questRowWords(_ s: Session) -> (title: String, sub: String) {
        guard let sent = s.questSent else { return (lexicon.t("quest.title"), lexicon.t("quest.rowSub")) }
        let f = PlannerFacts(app: self, dark: true)
        return (lexicon.t("quest.sentOn", ["d": f.dates.dMon(sent)]), lexicon.t("quest.againSub"))
    }

    // MARK: Лист

    /// Тап по строке: лист открывается, знак показан — считаем опросник отданным (веб: камеру наводят при нас).
    func openQuest(for s: Session) {
        quest = QuestState(recordId: s.id, isOpen: true)
        markQuestSent(s.id)
    }

    func closeQuest() { quest = QuestState() }

    /// Адрес страницы для записи листа.
    func questURL() -> URL? { quest.recordId.flatMap { _ in URL(string: QuestFlow.link(recordId: quest.recordId)) } }

    /// Отметка «отправлен» на показ знака и на отправку. Уже отмечено — дата не двигается.
    func markQuestSent(_ id: String) {
        guard let i = snapshot.sessions.firstIndex(where: { $0.id == id }) else { return }
        guard QuestFlow.markSent(&snapshot.sessions[i], at: now(), nowMs: nowMs) else { return }
        persist()
    }

    /// Запасной путь отправки: системного листа нет — ссылка в буфер (веб `quest.copiedTitle`).
    func copyQuestLink() {
        guard let id = quest.recordId else { return }
        markQuestSent(id)
        #if canImport(UIKit)
        UIPasteboard.general.string = QuestFlow.link(recordId: id)
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(QuestFlow.link(recordId: id), forType: .string)
        #endif
        quest.copied = true
    }

    // MARK: Приём ответа

    /// Слова заметки: приложение отдаёт домену свой каталог и свои даты.
    var questLabels: QuestLabels {
        let lex = lexicon, dates = DateText(language: language)
        return QuestLabels(text: { lex.t($0) }, date: { d in
            var c = DateComponents()
            (c.year, c.month, c.day, c.hour) = (d.year, d.month, d.day, 12)
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            return dates.dMonYear(cal.date(from: c) ?? Date())
        })
    }

    /// Вставка из листа: ответ идёт в запись листа.
    @discardableResult
    func applyPastedQuest() -> QuestOutcome {
        let out = receiveQuest(quest.paste, into: quest.recordId)
        switch out {
        case .applied: closeQuest()
        case .noAnswer: quest.message = lexicon.t("quest.pasteBad")
        case .bad: quest.message = lexicon.t("quest.badTitle")
        }
        return out
    }

    /// Ссылка своей схемы (`lightplan://…?ans=`): запись — по знаку `r` из самой ссылки.
    @discardableResult
    func openQuestLink(_ url: URL) -> QuestOutcome? {
        guard QuestFlow.isAppLink(url) else { return nil }
        return receiveQuest(url.absoluteString, into: nil)
    }

    /// Общий путь ссылки и вставки: разбор → черновик → форма записи с наложенным ответом.
    /// Выросшая встреча (`grewToId`) отдаёт ответ своей съёмке (веб L31425–31429).
    func receiveQuest(_ text: String, into recordId: String?) -> QuestOutcome {
        switch QuestParse.receive(text) {
        case .noAnswer: return .noAnswer
        case .bad: return .bad
        case .answer(let a, let linkId):
            var target = recordId ?? linkId
            if let t = target, let s = snapshot.sessions.first(where: { $0.id == t }), s.grewOn != nil, let g = s.grewToId,
               snapshot.sessions.contains(where: { $0.id == g }) { target = g }
            let known = target.flatMap { t in snapshot.sessions.contains { $0.id == t } ? t : nil }
            if let code = QuestParse.code(in: text) {
                questDrafts.hold(code: code, for: known, at: now())
                questDraftStore?.save(questDrafts)
            }
            if let known { openForm(editing: known) } else { openQuestMeeting() }
            let clash = layQuest(a)
            return .applied(clash: clash)
        }
    }

    /// Новая встреча под ответ без записи: жанр «Свадьба», если он в «Моих жанрах» (веб L31313–31321).
    private func openQuestMeeting() {
        openForm(day: nil, start: nil, fromLight: false, mode: .meet)
        if enabledGenres.contains(.wedding) { pickFormGenre(.wedding) }
    }

    /// Ответ ложится на открытую форму; подпись под формой — сколько расхождений. Возвращает их число.
    @discardableResult
    func layQuest(_ a: QuestAnswer) -> Int {
        guard var f = form else { return 0 }
        let pair = f.persons.count >= 2
        var q = QuestForm(p1Name: pair ? f.persons[0].name : "", p2Name: pair ? f.persons[1].name : "",
                          p1Phone: pair ? f.persons[0].phone : "", p2Phone: pair ? f.persons[1].phone : "",
                          notes: f.notes, hasPair: pair)
        let report = QuestMerge.apply(a, to: q, country: telCountry, labels: questLabels)
        q = report.form
        if pair {
            f.persons[0].name = q.p1Name; f.persons[1].name = q.p2Name
            f.persons[0].phone = q.p1Phone; f.persons[1].phone = q.p2Phone
        }
        f.notes = q.notes
        form = f
        var note = report.clash.isEmpty ? lexicon.t("quest.filled")
            : lexicon.t("quest.filledClash", ["list": lexicon.count("unit.clash", report.clash.count)])
        if report.truncated.count > 0 { note += " · " + lexicon.t("quest.cut", ["n": String(QuestAnswer.maxLength)]) }
        formNote = note
        formChanged()
        return report.clash.count
    }

    /// Запись сохранена — принятый ответ больше не нужен (веб не хранил его вовсе).
    func releaseQuestDraft(recordId: String, wasNew: Bool) {
        questDrafts.release(recordId)
        if wasNew { questDrafts.release(nil) }
        questDraftStore?.save(questDrafts)
    }

    /// Правка записи открыта заново, а ответ ещё лежит в черновике: он накладывается снова, повтор заметки не дублирует.
    func reapplyQuestDraft(for id: String) {
        guard let d = questDrafts.pending(for: id), case .success(let a) = QuestParse.decode(d.code) else { return }
        layQuest(a)
    }
}
