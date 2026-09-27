import Foundation

/// Вопрос студии «есть ли у вас бронь с этими номерами» (веб `#fLinkRow`,
/// `POST <шлюз>/booking/match`). Наружу уезжают номера — только по нажатию
/// (DECISIONS, «Связь со студией опознаётся по совпадению номеров»).
public struct BookingQuery: Sendable, Equatable {
    public var studioKey: String
    public var catalogId: String?
    /// Местная дата начала ячейки, «YYYY-MM-DD».
    public var date: String
    /// Часы ячейки, «HH:MM».
    public var from: String
    public var to: String
    /// Международные цифры всех номеров съёмки.
    public var phones: [String]

    public init(studioKey: String, catalogId: String?, date: String, from: String, to: String, phones: [String]) {
        self.studioKey = studioKey; self.catalogId = catalogId; self.date = date
        self.from = from; self.to = to; self.phones = phones
    }
}

/// Ответ студии: бронь, зал и её часы «HH:MM»; `nil` — совпадения нет.
public struct BookingAnswer: Sendable, Equatable {
    public var ref: String
    public var hallId: String?
    public var start: String?
    public var end: String?

    public init(ref: String, hallId: String? = nil, start: String? = nil, end: String? = nil) {
        self.ref = ref; self.hallId = hallId; self.start = start; self.end = end
    }
}

public protocol BookingMatching: Sendable {
    /// Бросает, если студия не ответила вовсе («студия не ответила»).
    func match(_ q: BookingQuery) async throws -> BookingAnswer?
}

/// Шлюз студии по сети. Адрес — тот же, что у веба (`STUDIO_API_DEFAULT`):
/// пока каталога нет, студия одна.
public struct HTTPBookingMatch: BookingMatching {
    public static let defaultBase = URL(string: "https://tomson-auth.alexeynovopashin.workers.dev")!
    let base: URL

    public init(base: URL = Self.defaultBase) { self.base = base }

    public func match(_ q: BookingQuery) async throws -> BookingAnswer? {
        var req = URLRequest(url: base.appendingPathComponent("booking/match"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(q.studioKey, forHTTPHeaderField: "X-Studio-Key")
        var body: [String: Any] = ["date": q.date, "from": q.from, "to": q.to, "phones": q.phones]
        body["studioId"] = q.catalogId ?? NSNull()
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return Self.answer(data)
    }

    /// Разбор ответа отдельно от сети — его проверяют тесты.
    static func answer(_ data: Data) -> BookingAnswer? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (o["match"] as? Bool) == true else { return nil }
        let ref = (o["bookingRef"] as? String) ?? (o["bookingRef"].map { "\($0)" } ?? "")
        return BookingAnswer(ref: ref, hallId: o["hallId"] as? String,
                             start: o["start"] as? String, end: o["end"] as? String)
    }
}
