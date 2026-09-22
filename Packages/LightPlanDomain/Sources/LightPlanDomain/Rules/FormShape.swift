import Foundation

/// Режим формы (веб `formKind`): встреча прячет всё, что про уже назначенную
/// съёмку, — обсуждать ещё нечего.
public enum FormMode: String, Sendable {
    case shoot, meet
}

/// Поле или блок формы, который показывается по жанру (веб `FORM_FIELDS`).
/// Порядок случаев — порядок строк таблицы веба; узлы разметки веба названы у
/// каждого случая.
public enum FormField: CaseIterable, Sendable {
    /// `fPayLabel`, `fPayGroup` — оплата.
    case payment
    /// `fWishLabel`, `fWishGroup` — пожелания к погоде.
    case wishes
    /// `fRefsLabel`, `fRefsGroup` — референсы.
    case references
    /// `fDelvLabel`, `fDelvGroup` — сдача материала: там, где есть кому сдавать.
    case delivery
    /// `fWhoLabel`, `fWhoGroup` — группа «кто»: клиента нет — нет и группы.
    case who
    /// `fContact`, `fClientTel` — клиент строкой, пока он человек и не пара.
    case contactLine
    /// `fP1Name`, `fP1Tel` — первый человек пары.
    case firstPerson
    /// `fP2Name`, `fP2Tel` — второй человек пары.
    case secondPerson
    /// `fOrgRow` — организатор у события, заказчик у заказа.
    case organization
    /// `fPerson`, `fPhone` — контактное лицо заказчика.
    case orderContact
    /// `fGuestsRow` — гости, мерка события дня.
    case guests
    /// `fPrepayRow` — предоплата.
    case prepay
    /// `fOrderLabel`, `fOrderGroup` — заказ: ТЗ и документы.
    case order
    /// `fModels` — модели: включает жанр поверх группы.
    case models
    /// `fBreed` — порода: снимают не человека.
    case breed
}

/// Состав формы по жанру — матрица полей `docs/12_CARD_ARCHITECTURE.md`,
/// записанная данными (веб `FORM_FIELDS` и `applyGenreShape`).
public enum FormShape {

    /// Показывается ли поле у жанра в этом режиме формы.
    public static func shows(_ field: FormField, genre: Genre?, mode: FormMode) -> Bool {
        let p = GenreProfile(genre)
        let sp = p.spec, gr = p.groupSpec, meet = mode == .meet
        switch field {
        case .payment, .wishes, .references: return !meet
        case .delivery: return sp.delivery && !meet
        case .who: return sp.client
        case .contactLine: return sp.client && !gr.order && p.persons.isEmpty
        case .firstPerson: return p.persons.count > 0
        case .secondPerson: return p.persons.count > 1
        case .organization: return gr.org
        case .orderContact: return gr.order
        case .guests: return gr.guests && !meet
        case .prepay: return gr.prepay && !meet
        case .order: return gr.order && !meet
        case .models: return gr.order && sp.models
        case .breed: return sp.breed && !meet
        }
    }

    /// Все поля, которые жанр показывает, в порядке таблицы.
    public static func fields(genre: Genre?, mode: FormMode) -> [FormField] {
        FormField.allCases.filter { shows($0, genre: genre, mode: mode) }
    }
}
