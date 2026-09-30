import Foundation

/// Опросник на карточке: когда строка есть, адрес страницы, отметка «отправлен», приём своей схемы
/// (веб `questFits`, `questLink`, `markQuestSent`; итерация 28, шаг 9; справка `docs/quest_reference.md` § 1, § 4).
public enum QuestFlow {
    /// Страница опросника. Одна на оба канала веба (`quest/` лежит в корне Pages).
    public static let page = "https://alexeynovopashin-lab.github.io/Light-Plan/quest/wedding.html"
    /// Куда страница вернёт ответ: адрес веб-приложения этого канала. Страница знает только `beta` и `main`; режим `c=app`
    /// (обратный адрес — своя схема) появится, когда разрешат править страницу (П1 в `docs/web_defects.md`).
    public static let channel = "beta"
    /// Своя схема приложения: `lightplan://…?ans=<код>`. Универсальные ссылки на бесплатной команде не проверены.
    public static let scheme = "lightplan"

    /// Строка опросника бывает у свадьбы: у встречи — пока она не выросла в съёмку, у съёмки — до неё.
    public static func fits(_ s: Session, phase: EventPhase) -> Bool {
        guard s.genre == .wedding else { return false }
        return s.kind == .meet ? s.grewOn == nil : phase == .before
    }

    /// Показана ли строка на карточке: подходит записи и не снята крестиком.
    public static func rowShown(_ s: Session, phase: EventPhase) -> Bool { fits(s, phase: phase) && !s.questOff }

    /// Адрес страницы; знак записи — только того вида, что пропускает страница (`^[a-z0-9]{1,32}$`).
    public static func link(recordId: String?) -> String {
        var url = page + "?c=" + channel
        if let id = recordId, !id.isEmpty, id.count <= 32,
           id.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) }) {
            url += "&r=" + id
        }
        return url
    }

    /// Отметка «отправлен»: ставится один раз, повторный показ знака дату не двигает (веб `markQuestSent`).
    /// `true` — запись изменена.
    @discardableResult
    public static func markSent(_ s: inout Session, at now: Date, nowMs: Int64) -> Bool {
        guard s.questSent == nil else { return false }
        s.questSent = now
        s.modifiedAt = nowMs
        return true
    }

    /// Ссылка своей схемы: ответ клиента, пришедший в приложение без вставки.
    public static func isAppLink(_ url: URL) -> Bool { url.scheme?.lowercased() == scheme }
}
