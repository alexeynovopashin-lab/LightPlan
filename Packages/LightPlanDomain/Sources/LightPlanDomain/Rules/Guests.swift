import Foundation

/// Число гостей в форме съёмки (поле-1, слова Алексея 25.10): «минимум 10, пусть так, но кнопка должна уменьшать число
/// до 1». От 1 до 10 шаг один гость, выше десяти — десяток (свадьбу считают десятками, как у веба `stepGuests`);
/// точное число вписывается в поле (веб `fGuestsVal`: только цифры, не больше четырёх, потолок 2000).
/// Ноль — не ответ, а пустая клетка: на экране «—».
public enum Guests {
    public static let max = 2000
    /// До этого числа включительно и от него вниз считают по одному.
    public static let singles = 10

    /// «+»: до десяти по одному, дальше на десяток; выше потолка не уходит.
    public static func more(_ n: Int) -> Int {
        let n = Swift.max(0, n)
        return n < singles ? n + 1 : Swift.min(max, n + 10)
    }

    /// «−»: с десяти и ниже по одному до нуля («—»); выше десяти на десяток, но не ниже десяти — «15» идёт в «10», а не в «5».
    public static func fewer(_ n: Int) -> Int {
        let n = Swift.min(max, Swift.max(0, n))
        return n <= singles ? Swift.max(0, n - 1) : Swift.max(singles, n - 10)
    }

    /// Что осталось от набранного: только цифры (вставленное «12 человек» → «12»), не больше четырёх, потолок 2000,
    /// без ведущих нулей. Пустой ввод остаётся пустым, «0» остаётся «0» (поле ещё не покинули).
    public static func sanitize(_ raw: String) -> String {
        let digits = raw.unicodeScalars.filter { $0.value >= 0x30 && $0.value <= 0x39 }.prefix(4)
        guard !digits.isEmpty else { return "" }
        let n = Int(String(String.UnicodeScalarView(digits))) ?? 0
        return String(Swift.min(max, n))
    }

    /// Что стоит в поле, пока его правят, когда число гостей изменилось. Набранное совпадает с числом — поле не трогаем
    /// (набранный «0» остаётся «0», пока из поля не вышли; ревью GPT к 17542a4); число ушло иначе, кнопкой, — поле берёт его.
    public static func editingText(_ text: String, value: Int) -> String {
        if parse(text) == value { return text }
        return value == 0 ? "" : String(value)
    }

    /// Набранное → число; пусто и «не число» — 0.
    public static func parse(_ raw: String) -> Int { Int(sanitize(raw)) ?? 0 }
}

extension EventForm {
    public mutating func moreGuests() { guests = Guests.more(guests) }
    public mutating func fewerGuests() { guests = Guests.fewer(guests) }
    /// Ввод цифрами в поле числа гостей.
    public mutating func typeGuests(_ raw: String) { guests = Guests.parse(raw) }
}
