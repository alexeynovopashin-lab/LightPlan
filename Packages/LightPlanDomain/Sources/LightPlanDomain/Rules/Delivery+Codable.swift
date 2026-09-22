import Foundation
import LightPlanCore

/// `mode`, `days` (веб `delivery`).
extension DeliverySetting: Codable {
    enum CodingKeys: String, CodingKey { case mode, days }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(mode: try c.decodeLenient(DeliveryMode.self, forKey: .mode, default: .genre),
                  days: try c.decodeIfPresent(Int.self, forKey: .days) ?? DeliverySetting.standard.days)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode.rawValue, forKey: .mode)
        try c.encode(days, forKey: .days)
    }
}

/// `pay`, `dur`, `delv`, `rate`, `pre`, `delvDays` (веб `genrePrefs[жанр]`).
extension GenrePrefs: Codable {
    enum CodingKeys: String, CodingKey { case pay, dur, delv, rate, pre, delvDays }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(pay: try c.decodeLenient(PayKind.self, forKey: .pay),
                  duration: try c.decodeTriState(Int.self, forKey: .dur),
                  deadline: try c.decodeDeadlineChoiceIfPresent(forKey: .delv),
                  rate: try c.decodeIfPresent(Decimal.self, forKey: .rate),
                  prepayShare: try c.decodeIfPresent(Double.self, forKey: .pre),
                  deliveryDays: try c.decodeIfPresent(Int.self, forKey: .delvDays))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeLenient(pay, forKey: .pay)
        try c.encodeTriState(duration, forKey: .dur)
        try c.encodeDeadlineChoiceIfPresent(deadline, forKey: .delv)
        try c.encodeIfPresent(rate, forKey: .rate)
        try c.encodeIfPresent(prepayShare, forKey: .pre)
        try c.encodeIfPresent(deliveryDays, forKey: .delvDays)
    }
}
