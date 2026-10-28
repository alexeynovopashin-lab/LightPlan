import Foundation

/// Подпись занятости в клетке месяца (Алексей 28.10: «не дорога в, а просто дорога, не печать альбомов, а просто
/// печать»). В клетке нет места на фразу, поэтому у заметки, вписанной руками, показывается её первое слово; без заметки —
/// слово вида («Дорога», «Выходной»…). Только клетка месяца: неделя, лист блока и поиск держат заметку целиком.
public enum BlockMonthLabel {
    /// Языки без пробелов между словами: заметка остаётся как набрана (обрезка только по ширине клетки).
    public static func splitsWords(language: String) -> Bool {
        let base = language.lowercased().prefix { $0 != "-" && $0 != "_" }
        return base != "ja" && base != "zh"
    }

    /// `kindWord` — слово вида на языке приложения; `note` — заметка блока как записана.
    /// Слово из одного знака и слово из одной пунктуации («в», «—») пропускаются; пунктуация по краям слова срезается.
    /// Нет подходящего слова — слово вида.
    public static func text(note: String, kindWord: String, language: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return kindWord }
        guard splitsWords(language: language) else { return trimmed }
        for raw in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            let word = raw.trimmingCharacters(in: edge)
            if word.count >= 2 { return word }
        }
        return kindWord
    }

    private static let edge = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
}
