import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Опросник клиента: разбор кода ответа, сверка с записью, повтор, черновик (итерация 28, шаг 8;
/// справка `docs/quest_reference.md` §§ 1, 3, 5; ошибки веба А3–А5). Ожидаемое в фикстурах посчитано `questDecode` беты.
@Suite struct QuestTests {
    static let ru = TelCountry.of("RU")!

    /// Слова каталога словами русского: как в приложении, чтобы тесты читались глазами.
    static let words: [String: String] = [
        "quest.head": "Из опроса:", "quest.clash": "Не сходится с опросом:", "person.bride": "Невеста", "person.groom": "Жених",
        "form.phone": "Телефон", "quest.social": "Соцсеть", "quest.msgr": "Мессенджер", "quest.date": "Дата свадьбы",
        "quest.reg": "Роспись", "quest.church": "Венчание", "quest.offsite": "Выездная", "quest.party": "Банкет",
        "pane.guests": "Гостей", "quest.parents": "Родители", "quest.witnesses": "Свидетели", "quest.host": "Ведущий",
        "quest.car": "Автомобиль", "quest.suit": "Костюм жениха", "quest.dress": "Платье", "quest.music": "Музыканты",
        "quest.finale": "Финал вечера", "quest.pets": "Животные", "quest.rites": "Обычаи и ограничения",
        "quest.places": "Места", "quest.wishes": "Пожелания", "quest.pin": "Pinterest",
    ]
    static let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    static let labels = QuestLabels(text: { words[$0] ?? "?\($0)" },
                                    date: { "\($0.day) \(months[$0.month - 1]) \($0.year)" })

    static func answer(_ pairs: KeyValuePairs<String, String>) -> QuestAnswer {
        var v: [String: String] = [:]
        for (k, s) in pairs { v[k] = s }
        return QuestAnswer(values: v)
    }
    static func apply(_ a: QuestAnswer, _ f: QuestForm = QuestForm()) -> QuestReport {
        QuestMerge.apply(a, to: f, country: ru, labels: labels)
    }
    static func decoded(_ code: String) -> QuestAnswer? {
        if case .success(let a) = QuestParse.decode(code) { return a }
        return nil
    }

    // MARK: - Разбор

    @Test func everyRealLinkGivesWhatTheWebGives() {
        for link in QuestFixtures.links {
            switch QuestParse.receive(link.url) {
            case .answer(let a, _):
                #expect(a.values == link.expected, "\(link.name): \(link.note)")
                #expect(a.truncated == link.truncated, "\(link.name): признак «обрезано»")
            case .bad(let f) where link.expected.isEmpty:
                #expect(f == .empty, "\(link.name)")
            default:
                Issue.record("\(link.name): ссылка не разобралась")
            }
        }
    }

    @Test func fullAnketLinkHas25FieldsAndIsAsLongAsMeasured() throws {
        let full = try #require(QuestFixtures.links.first { $0.name == "full25" })
        #expect(full.expected.count == 25)
        #expect(Set(full.expected.keys) == Set(QuestAnswer.keys))
        // Справка: ответ ~1340 знаков; пример этого шага — того же порядка, а не 424 из DECISIONS.
        let code = try #require(QuestParse.code(in: full.url))
        #expect(code.count > 1000, "код \(code.count) знаков")
    }

    @Test func cutAnswersReportTruncation() throws {
        let cut = try #require(QuestFixtures.links.first { $0.name == "cut601" })
        let cutCode = try #require(QuestParse.code(in: cut.url))
        let a = try #require(Self.decoded(cutCode))
        #expect(a["ms"]?.utf16.count == 600 && a.truncated.contains("ms"), "601 → 600, с признаком")
        #expect(a["pr"]?.utf16.count == 600 && a.truncated.contains("pr"), "пробелы по краям срезаются до обрезки")
        #expect(a["re"]?.utf16.count == 600 && !a.truncated.contains("re"), "ровно 600 — не обрезано")
        #expect(a.wasTruncated)
    }

    @Test func brokenCodesAreStatesNotCrashes() {
        for b in QuestFixtures.broken {
            let r = QuestParse.decode(b.code)
            guard case .failure = r else { Issue.record("\(b.name): ждали отказ"); continue }
        }
        #expect(QuestParse.decode("!!!") == .failure(.notCode))
        #expect(QuestParse.decode("0Y3RgtC-INC90LUganNvbg") == .failure(.notJSON))
        #expect(QuestParse.decode("WyJiIiwi0JrQsNGC0Y8iXQ") == .failure(.notObject), "массив — не объект")
        #expect(QuestParse.decode("NDI") == .failure(.notObject))
        #expect(QuestParse.decode("e30") == .failure(.empty), "{} — ни одного ответа")
        #expect(QuestParse.receive("https://x.org/beta/?ans=!!!") == .noAnswer, "нечитаемое в адресе — как пустое")
        #expect(QuestParse.receive("https://x.org/beta/?ans=e30") == .bad(.empty))
    }

    @Test func textWithoutAnswerIsNoAnswer() {
        #expect(QuestParse.receive("привет, вот ответы") == .noAnswer)
        #expect(QuestParse.receive("") == .noAnswer)
        #expect(QuestParse.receive("https://x.org/beta/?r=abc") == .noAnswer)
        #expect(QuestParse.receive("https://x.org/beta/?bans=e30") == .noAnswer, "ans= только как параметр, не кусок слова")
    }

    @Test func wholeMessageWorksAndRecordIdIsCarried() throws {
        let pair = try #require(QuestFixtures.links.first { $0.name == "pairOnly" })
        let code = try #require(QuestParse.code(in: pair.url))
        let msg = "Ответы к съёмке: https://x.org/beta/?ans=\(code)&r=k3x9 — спасибо!"
        guard case .answer(let a, let id) = QuestParse.receive(msg) else { Issue.record("не разобрал"); return }
        #expect(a["b"] == "Лена" && id == "k3x9")
        // Знак не того вида (заглавные, 33 знака) — отбрасывается, как на странице.
        guard case .answer(_, let bad) = QuestParse.receive("?ans=\(code)&r=ABC") else { Issue.record("не разобрал"); return }
        #expect(bad == nil)
        guard case .answer(_, let long) = QuestParse.receive("?ans=\(code)&r=" + String(repeating: "a", count: 33)) else { Issue.record("не разобрал"); return }
        #expect(long == nil)
        guard case .answer(_, let none) = QuestParse.receive("?ans=\(code)") else { Issue.record("не разобрал"); return }
        #expect(none == nil)
    }

    @Test func foreignKeysAndNonStringsAreDropped() throws {
        let f = try #require(QuestFixtures.links.first { $0.name == "foreign" })
        #expect(f.expected == ["b": "Катя"], "чужой ключ, число, массив, null, true и пробелы — не ответ")
    }

    // MARK: - Сверка

    @Test func emptyFieldsAreFilledQuietly() throws {
        let full = try #require(QuestFixtures.links.first { $0.name == "full25" })
        let r = Self.apply(QuestAnswer(values: full.expected))
        #expect(r.form.p1Name == "Екатерина Соколова" && r.form.p2Name == "Вячеслав Орлов")
        #expect(r.form.p1Phone == "8 913 111-22-33" || r.form.p1Phone == "+7 913 111-22-33", "телефон формата приложения: \(r.form.p1Phone)")
        #expect(r.clash.isEmpty && !r.alreadyApplied)
        let lines = r.form.notes.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.first == "Из опроса:")
        #expect(r.form.notes.contains("Дата свадьбы: 15 июня 2027"))
        #expect(r.form.notes.contains("Гостей: 48"))
        #expect(!r.form.notes.contains("Невеста:"), "у пары имена в полях, а не в заметках")
        let paragraphs = r.form.notes.components(separatedBy: "\n\n")
        #expect(paragraphs.count == 5, "блок «Из опроса» и абзацы обычаев, мест, пожеланий, Pinterest: \(paragraphs.count)")
        #expect(paragraphs.first?.split(separator: "\n").count == 19, "заголовок + 17 ответов (без имён и телефонов у пары) + вторая строка «Родителей» из перевода строки")
    }

    @Test func mismatchesGoToNotesAndBusyFieldsAreNotTouched() {
        let f = QuestForm(p1Name: "Лена", p2Name: "Тимур", p1Phone: "+7 913 343-53-63", p2Phone: "+7 913 343-53-64",
                          notes: "Завтра. Половина внесена.")
        let a = Self.answer(["b": "Елена", "bt": "8 913 343 53 63", "g": "Тимур", "gt": "+7 913 000-00-00", "d": "2027-06-15", "w": "Х"])
        let r = Self.apply(a, f)
        #expect(r.form.p1Name == "Лена" && r.form.p2Name == "Тимур", "занятое не переписывается")
        #expect(r.form.p1Phone == "+7 913 343-53-63" && r.form.p2Phone == "+7 913 343-53-64")
        // Как в замере справки: «Лена / Елена» — терпимый шум, «8 913…» и «+7 913…» — не расхождение.
        #expect(r.clash == ["Невеста: Лена / Елена", "Жених: +7 913 343-53-64 / +7 913 000-00-00"])
        #expect(r.form.notes == "Завтра. Половина внесена.\n\nИз опроса:\nДата свадьбы: 15 июня 2027\n\nПожелания: Х\n\nНе сходится с опросом:\nНевеста: Лена / Елена\nЖених: +7 913 343-53-64 / +7 913 000-00-00")
    }

    @Test func caseYoAndSpacesAreNotAMismatch() {
        let r = Self.apply(Self.answer(["b": "ЕЛЕНА  Королёва", "g": "тимур"]),
                           QuestForm(p1Name: "Елена Королева", p2Name: "Тимур"))
        #expect(r.clash.isEmpty && r.form.notes.isEmpty, "регистр, «ё» и двойной пробел — тот же человек")
    }

    @Test func numbersInAnyNotationAreOnePerson() {
        let r = Self.apply(Self.answer(["bt": "89131112233", "gt": "+79139998877"]),
                           QuestForm(p1Phone: "+7 913 111-22-33", p2Phone: "8 913 999-88-77"))
        #expect(r.clash.isEmpty)
    }

    @Test func noPairMovesNamesAndPhonesToNotes() {
        let r = Self.apply(Self.answer(["b": "Катя", "bt": "8 913 111-22-33", "g": "Слава", "w": "Х"]), QuestForm(hasPair: false))
        #expect(r.form.p1Name.isEmpty && r.form.p1Phone.isEmpty)
        #expect(r.form.notes == "Из опроса:\nНевеста: Катя\nТелефон: 8 913 111-22-33\nЖених: Слава\n\nПожелания: Х")
    }

    @Test func photographersNotesStayOnTop() {
        let r = Self.apply(Self.answer(["n": "40"]), QuestForm(notes: "  Договорились на пятницу  "))
        #expect(r.form.notes == "Договорились на пятницу\n\nИз опроса:\nГостей: 40")
    }

    @Test func dateIsWordsOrAsCame() {
        #expect(Self.apply(Self.answer(["d": "2027-06-15"])).form.notes.contains("Дата свадьбы: 15 июня 2027"))
        #expect(Self.apply(Self.answer(["d": "2027-02-30"])).form.notes.contains("Дата свадьбы: 2027-02-30"))
        #expect(Self.apply(Self.answer(["d": "летом"])).form.notes.contains("Дата свадьбы: летом"))
        #expect(Self.apply(Self.answer(["d": "2028-02-29"])).form.notes.contains("29 февраля 2028"), "високосный")
    }

    @Test func pairOnlyAnswerLeavesNotesEmpty() {
        let r = Self.apply(Self.answer(["b": "Катя", "g": "Слава"]))
        #expect(r.form.p1Name == "Катя" && r.form.notes.isEmpty && !r.alreadyApplied)
    }

    // MARK: - Повтор (ошибка веба А4)

    @Test func applyingTheSameAnswerTwiceDoesNotAddSecondBlock() {
        let a = Self.answer(["b": "Елена", "g": "Тимур", "d": "2027-06-15", "w": "Х"])
        let once = Self.apply(a, QuestForm(p1Name: "Лена", notes: "Завтра."))
        #expect(!once.alreadyApplied && once.clash.count == 1)
        let twice = Self.apply(a, once.form)
        #expect(twice.alreadyApplied)
        #expect(twice.form.notes == once.form.notes, "заметки не изменились: ни второго «Из опроса», ни второго «Не сходится»")
        #expect(twice.form.notes.components(separatedBy: "Из опроса:").count == 2)
        #expect(Self.apply(a, twice.form).form == twice.form, "и в третий раз то же")
    }

    @Test func aDifferentAnswerIsAppendedAsANewBlock() {
        let first = Self.apply(Self.answer(["w": "Х"]))
        let second = Self.apply(Self.answer(["w": "Y"]), first.form)
        #expect(!second.alreadyApplied)
        #expect(second.form.notes == "Пожелания: Х\n\nПожелания: Y")
    }

    @Test func aBlockTheUserTrimmedIsNotMistakenForApplied() {
        let a = Self.answer(["d": "2027-06-15", "w": "Х"])
        var f = Self.apply(a).form
        f.notes = "Из опроса:\nДата свадьбы: 15 июня 2027"   // абзац «Пожелания» стёрт вручную
        let r = Self.apply(a, f)
        #expect(!r.alreadyApplied, "не тот же блок — дописываем целиком, ничего не теряя")
    }

    // Ревью GPT к faaca1a.

    @Test func aShortAnswerIsNotMistakenForALongerOneAlreadyThere() {
        let long = Self.apply(Self.answer(["w": "ХХ"]))
        let short = Self.apply(Self.answer(["w": "Х"]), long.form)
        #expect(!short.alreadyApplied, "«Х» — новый ответ, а не «ХХ» во второй раз")
        #expect(short.form.notes == "Пожелания: ХХ\n\nПожелания: Х")
        let again = Self.apply(Self.answer(["w": "Х"]), short.form)
        #expect(again.alreadyApplied && again.form.notes == short.form.notes, "а теперь это уже повтор")
    }

    @Test func aBlockInsideALongerParagraphIsNotARepeat() {
        let r = Self.apply(Self.answer(["w": "Х"]), QuestForm(notes: "Мои: Пожелания: Х и ещё"))
        #expect(!r.alreadyApplied && r.form.notes.hasSuffix("\n\nПожелания: Х"))
    }

    @Test func aNameOnlyMismatchIsNotAppendedTwice() {
        let a = Self.answer(["b": "Мария"])
        let once = Self.apply(a, QuestForm(p1Name: "Анна"))
        #expect(once.form.notes == "Не сходится с опросом:\nНевеста: Анна / Мария" && !once.alreadyApplied)
        let twice = Self.apply(a, once.form)
        #expect(twice.alreadyApplied && twice.form.notes == once.form.notes, "ответ из одного имени: повтор узнаётся по абзацу расхождений")
        #expect(twice.clash == ["Невеста: Анна / Мария"], "показать расхождение подписью формы можно и на повторе")
    }

    @Test func recordIdComesFromTheSameLinkAsTheAnswer() throws {
        let pair = try #require(QuestFixtures.links.first { $0.name == "pairOnly" })
        let code = try #require(QuestParse.code(in: pair.url))
        // Две ссылки в сообщении: знак второй не принадлежит ответу первой.
        let two = "Первая https://x.org/beta/?ans=\(code) вторая https://x.org/beta/?ans=e30&r=zzz"
        guard case .answer(_, let id) = QuestParse.receive(two) else { Issue.record("не разобрал"); return }
        #expect(id == nil)
        // Вплотную, через знак препинания: границей служит и он, не только пробел.
        for sep in [";", ",", ")", "\n", " | "] {
            guard case .answer(_, let near) = QuestParse.receive("https://x.org/beta/?ans=\(code)\(sep)https://x.org/beta/?r=zzz") else { Issue.record("не разобрал"); return }
            #expect(near == nil, "разделитель «\(sep)»")
        }
        guard case .answer(_, let own) = QuestParse.receive("(https://x.org/beta/?ans=\(code)&r=k3x9), спасибо") else { Issue.record("не разобрал"); return }
        #expect(own == "k3x9", "скобка и запятая вокруг своей ссылки не мешают")
        // Без разделителя вообще: одна ссылка кончается там, где начинается следующая.
        guard case .answer(_, let glued) = QuestParse.receive("https://x.org/beta/?ans=\(code) https://x.org/beta/?r=zzz https://x.org/beta/?ans=\(code)&r=own1") else { Issue.record("не разобрал"); return }
        #expect(glued == nil, "берётся первый ответ и его ссылка")
        guard case .answer(_, let prefixed) = QuestParse.receive("https://a.org/?r=old1https://x.org/beta/?ans=\(code)") else { Issue.record("не разобрал"); return }
        #expect(prefixed == nil, "знак ссылки, что стоит вплотную перед этой, — чужой")
        guard case .answer(_, let upper) = QuestParse.receive("https://a.org/?r=old1&z=1HTTPS://x.org/beta/?ans=\(code)") else { Issue.record("не разобрал"); return }
        #expect(upper == nil, "схема в любом регистре")
        guard case .answer(_, let frag) = QuestParse.receive("https://x.org/beta/?ans=\(code)#preview&r=other") else { Issue.record("не разобрал"); return }
        #expect(frag == nil, "знак во фрагменте после «#» — не параметр запроса")
        guard case .answer(_, let beforeFrag) = QuestParse.receive("https://x.org/beta/?ans=\(code)&r=k3x9#top") else { Issue.record("не разобрал"); return }
        #expect(beforeFrag == "k3x9")
        // Промежуточный параметр с точкой или %, что дописал мессенджер, ссылку не рвёт.
        guard case .answer(_, let mid) = QuestParse.receive("https://x.org/beta/?r=k3x9&source=photo.story&ans=\(code)") else { Issue.record("не разобрал"); return }
        #expect(mid == "k3x9")
        guard case .answer(_, let tail) = QuestParse.receive("https://x.org/beta/?ans=\(code)&utm=a%20b.c&r=k3x9") else { Issue.record("не разобрал"); return }
        #expect(tail == "k3x9")
        // Знак стоит до ответа в той же ссылке — годится.
        guard case .answer(_, let before) = QuestParse.receive("Вот https://x.org/beta/?r=k3x9&ans=\(code) спасибо") else { Issue.record("не разобрал"); return }
        #expect(before == "k3x9")
        // Знак другой ссылки, что стоит раньше, тоже не в счёт.
        guard case .answer(_, let other) = QuestParse.receive("https://x.org/beta/?r=aaa и https://x.org/beta/?ans=\(code)") else { Issue.record("не разобрал"); return }
        #expect(other == nil)
    }

    @Test func truncationIsReportedThroughApply() throws {
        let cut = try #require(QuestFixtures.links.first { $0.name == "cut601" })
        let r = Self.apply(QuestAnswer(values: cut.expected, truncated: cut.truncated))
        #expect(r.truncated == ["ms", "pr", "w"])
    }

    // MARK: - Черновик (ошибка веба А3)

    @Test func draftSurvivesUntilReleased() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var d = QuestDrafts()
        d.hold(code: "AAA", for: "k3x9", at: t0)
        d.hold(code: "BBB", for: nil, at: t0)
        #expect(d.pending(for: "k3x9")?.code == "AAA" && d.pending(for: nil)?.code == "BBB" && d.pending(for: "zzz") == nil)
        d.hold(code: "CCC", for: "k3x9", at: t0.addingTimeInterval(60))
        #expect(d.pending(for: "k3x9")?.code == "CCC", "новый ответ той же записи заменяет прежний")
        d.release("k3x9")
        #expect(d.pending(for: "k3x9") == nil && d.pending(for: nil)?.code == "BBB")
        #expect(d.pending(for: "")?.code == "BBB", "пустой знак — то же, что нет записи")
    }

    @Test func draftsOlderThanThirtyDaysAreDropped() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var d = QuestDrafts()
        d.hold(code: "old", for: "a", at: t0)
        d.hold(code: "new", for: "b", at: t0.addingTimeInterval(20 * 86_400))
        let early = d.prune(now: t0.addingTimeInterval(29 * 86_400))
        #expect(!early, "29 дней — ещё живой")
        let late = d.prune(now: t0.addingTimeInterval(31 * 86_400))
        #expect(late)
        #expect(d.pending(for: "a") == nil && d.pending(for: "b")?.code == "new")
    }

    @Test func draftAppliedAfterFormWasClosedGivesTheSameNotes() throws {
        // Черновик хранит код; форма закрыта без «Сохранить»; ответ возвращается из черновика и ложится ровно раз.
        let link = try #require(QuestFixtures.links.first { $0.name == "offsiteYes" })
        var drafts = QuestDrafts()
        let code = try #require(QuestParse.code(in: link.url))
        drafts.hold(code: code, for: "k1", at: Date(timeIntervalSince1970: 1_800_000_000))
        let saved = try JSONDecoder().decode(QuestDrafts.self, from: JSONEncoder().encode(drafts))
        let held = try #require(saved.pending(for: "k1"))
        let a = try #require(Self.decoded(held.code))
        let r1 = Self.apply(a)
        let r2 = Self.apply(a, r1.form)
        #expect(r1.form.notes.contains("Выездная: да") && r2.form.notes == r1.form.notes)
    }
}
