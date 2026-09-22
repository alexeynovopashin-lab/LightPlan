import Foundation
import LightPlanCore

/// Чтение и запись снимка (итерация 12). Ключи — те, что названы в
/// комментариях `Session.swift` один к одному (файл писался заранее именно
/// под это). Синтез Codable здесь не годится: часть полей снисходительная
/// (`Coding/LenientCoding.swift`) — незнакомый код не должен ронять всю
/// запись, а синтез уронил бы.
extension Session: Codable {
    enum CodingKeys: String, CodingKey {
        case id, kind, date, min, end, dur, type, sub
        case contact, clientTel, notes, orgId, person, phone, persons
        case place, placeTown, placeAddr, placeLat, placeLon, placeCity
        case studioId, hallId, rentFrom, rentTo, bookingRef, rentReq
        case wish, warn, deadlineChoice, delivered, deliveredAt
        case pay, rate, units, expense, prepay, currency
        case guests, trip, tripManual, tripPlace, brief, models, breed
        case docs, gear, playlist
        case questSent, questOff, fromMeetOn, fromMeetId, grewOn, grewToId, dayMoved
        case route, synced, telLog, rep, doneAt, icsSig, icsAt, mt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let kind = try c.decodeLenient(RecordKind.self, forKey: .kind, default: .shoot)
        guard let dateString = try c.decodeIfPresent(String.self, forKey: .date),
              let day = CivilDate(snapshotString: dateString) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "день записи не разобрался")
        }
        let start = try c.decodeIfPresent(Int.self, forKey: .min) ?? 0
        self.init(id: id, kind: kind, day: day, start: start)

        end = try c.decodeIfPresent(Int.self, forKey: .end)
        duration = try c.decodeIfPresent(Int.self, forKey: .dur)
        genre = try c.decodeLenient(Genre.self, forKey: .type)
        subGenre = try c.decodeLenient(SubGenre.self, forKey: .sub)

        contact = try c.decodeIfPresent(String.self, forKey: .contact) ?? ""
        clientPhone = try c.decodeIfPresent(String.self, forKey: .clientTel) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        orgId = try c.decodeIfPresent(String.self, forKey: .orgId)
        orderPerson = try c.decodeIfPresent(String.self, forKey: .person) ?? ""
        orderPhone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        persons = try c.decodeIfPresent([Person].self, forKey: .persons) ?? []

        place = try c.decodeIfPresent(String.self, forKey: .place) ?? ""
        placeTown = try c.decodeIfPresent(String.self, forKey: .placeTown) ?? ""
        placeAddress = try c.decodeIfPresent(String.self, forKey: .placeAddr) ?? ""
        latitude = try c.decodeIfPresent(Double.self, forKey: .placeLat)
        longitude = try c.decodeIfPresent(Double.self, forKey: .placeLon)
        placeIsCity = try c.decodeIfPresent(Bool.self, forKey: .placeCity) ?? false
        studioId = try c.decodeIfPresent(String.self, forKey: .studioId)
        hallId = try c.decodeIfPresent(String.self, forKey: .hallId)
        rentFrom = try c.decodeIfPresent(Int.self, forKey: .rentFrom)
        rentTo = try c.decodeIfPresent(Int.self, forKey: .rentTo)
        bookingRef = try c.decodeIfPresent(String.self, forKey: .bookingRef)
        rentRequest = try c.decodeIfPresent(RentRequest.self, forKey: .rentReq)

        wishes = try c.decodeLenientArray(Wish.self, forKey: .wish)
        wishWarning = try c.decodeIfPresent(WishWarning.self, forKey: .warn)

        deadline = try c.decodeDeadlineChoice(forKey: .deadlineChoice)
        delivered = try c.decodeIfPresent(Bool.self, forKey: .delivered) ?? false
        deliveredAt = try c.decodeIfPresent(String.self, forKey: .deliveredAt).flatMap(SnapshotDate.parse)

        pay = try c.decodeLenient(PayKind.self, forKey: .pay)
        rate = try c.decodeIfPresent(Decimal.self, forKey: .rate)
        units = try c.decodeIfPresent(Decimal.self, forKey: .units) ?? 0
        expense = try c.decodeIfPresent(Decimal.self, forKey: .expense) ?? 0
        prepay = try c.decodeIfPresent(Decimal.self, forKey: .prepay) ?? 0
        currency = try c.decodeLenient(Currency.self, forKey: .currency)

        guests = try c.decodeIfPresent(Int.self, forKey: .guests) ?? 0
        trip = try c.decodeIfPresent(Bool.self, forKey: .trip) ?? false
        tripManual = try c.decodeIfPresent(Bool.self, forKey: .tripManual) ?? false
        tripPlace = try c.decodeIfPresent(String.self, forKey: .tripPlace) ?? ""
        brief = try c.decodeIfPresent(String.self, forKey: .brief) ?? ""
        models = try c.decodeIfPresent(String.self, forKey: .models) ?? ""
        breed = try c.decodeIfPresent(String.self, forKey: .breed) ?? ""
        docs = try c.decodeIfPresent([Attachment].self, forKey: .docs) ?? []
        gear = try c.decodeIfPresent([String].self, forKey: .gear) ?? []
        playlist = try c.decodeIfPresent(String.self, forKey: .playlist)

        questSent = try c.decodeIfPresent(String.self, forKey: .questSent).flatMap(SnapshotDate.parse)
        questOff = try c.decodeIfPresent(Bool.self, forKey: .questOff) ?? false
        fromMeetOn = try c.decodeIfPresent(String.self, forKey: .fromMeetOn).flatMap { CivilDate(snapshotString: $0) }
        fromMeetId = try c.decodeIfPresent(String.self, forKey: .fromMeetId)
        grewOn = try c.decodeIfPresent(String.self, forKey: .grewOn).flatMap { CivilDate(snapshotString: $0) }
        grewToId = try c.decodeIfPresent(String.self, forKey: .grewToId)
        dayMoved = try c.decodeIfPresent(DayMoved.self, forKey: .dayMoved)

        route = try c.decodeIfPresent([RoutePoint].self, forKey: .route) ?? []
        calendar = try c.decodeLenient(CalendarService.self, forKey: .synced)
        telLog = try c.decodeIfPresent([TelLogEntry].self, forKey: .telLog) ?? []
        repeatInfo = try c.decodeIfPresent(Repeat.self, forKey: .rep)
        doneAt = try c.decodeIfPresent(Int.self, forKey: .doneAt)
        icsSignature = try c.decodeIfPresent(String.self, forKey: .icsSig)
        icsImportedAt = try c.decodeIfPresent(Int64.self, forKey: .icsAt)
        modifiedAt = try c.decodeIfPresent(Int64.self, forKey: .mt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(day.snapshotString, forKey: .date)
        try c.encode(start, forKey: .min)
        try c.encodeIfPresent(end, forKey: .end)
        try c.encodeIfPresent(duration, forKey: .dur)
        try c.encodeLenient(genre, forKey: .type)
        try c.encodeLenient(subGenre, forKey: .sub)

        try c.encode(contact, forKey: .contact)
        try c.encode(clientPhone, forKey: .clientTel)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(orgId, forKey: .orgId)
        try c.encode(orderPerson, forKey: .person)
        try c.encode(orderPhone, forKey: .phone)
        try c.encode(persons, forKey: .persons)

        try c.encode(place, forKey: .place)
        try c.encode(placeTown, forKey: .placeTown)
        try c.encode(placeAddress, forKey: .placeAddr)
        try c.encodeIfPresent(latitude, forKey: .placeLat)
        try c.encodeIfPresent(longitude, forKey: .placeLon)
        try c.encode(placeIsCity, forKey: .placeCity)
        try c.encodeIfPresent(studioId, forKey: .studioId)
        try c.encodeIfPresent(hallId, forKey: .hallId)
        try c.encodeIfPresent(rentFrom, forKey: .rentFrom)
        try c.encodeIfPresent(rentTo, forKey: .rentTo)
        try c.encodeIfPresent(bookingRef, forKey: .bookingRef)
        try c.encodeIfPresent(rentRequest, forKey: .rentReq)

        try c.encodeLenientArray(wishes, forKey: .wish)
        try c.encodeIfPresent(wishWarning, forKey: .warn)

        try c.encodeDeadlineChoice(deadline, forKey: .deadlineChoice)
        try c.encode(delivered, forKey: .delivered)
        try c.encodeIfPresent(deliveredAt.map(SnapshotDate.format), forKey: .deliveredAt)

        try c.encodeLenient(pay, forKey: .pay)
        try c.encodeIfPresent(rate, forKey: .rate)
        try c.encode(units, forKey: .units)
        try c.encode(expense, forKey: .expense)
        try c.encode(prepay, forKey: .prepay)
        try c.encodeLenient(currency, forKey: .currency)

        try c.encode(guests, forKey: .guests)
        try c.encode(trip, forKey: .trip)
        try c.encode(tripManual, forKey: .tripManual)
        try c.encode(tripPlace, forKey: .tripPlace)
        try c.encode(brief, forKey: .brief)
        try c.encode(models, forKey: .models)
        try c.encode(breed, forKey: .breed)
        try c.encode(docs, forKey: .docs)
        try c.encode(gear, forKey: .gear)
        try c.encodeIfPresent(playlist, forKey: .playlist)

        try c.encodeIfPresent(questSent.map(SnapshotDate.format), forKey: .questSent)
        try c.encode(questOff, forKey: .questOff)
        try c.encodeIfPresent(fromMeetOn?.snapshotString, forKey: .fromMeetOn)
        try c.encodeIfPresent(fromMeetId, forKey: .fromMeetId)
        try c.encodeIfPresent(grewOn?.snapshotString, forKey: .grewOn)
        try c.encodeIfPresent(grewToId, forKey: .grewToId)
        try c.encodeIfPresent(dayMoved, forKey: .dayMoved)

        try c.encode(route, forKey: .route)
        try c.encodeLenient(calendar, forKey: .synced)
        try c.encode(telLog, forKey: .telLog)
        try c.encodeIfPresent(repeatInfo, forKey: .rep)
        try c.encodeIfPresent(doneAt, forKey: .doneAt)
        try c.encodeIfPresent(icsSignature, forKey: .icsSig)
        try c.encodeIfPresent(icsImportedAt, forKey: .icsAt)
        try c.encodeIfPresent(modifiedAt, forKey: .mt)
    }
}

/// `n`, `tel`.
extension Person: Codable {
    enum CodingKeys: String, CodingKey { case n, tel }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decodeIfPresent(String.self, forKey: .n) ?? "",
                  phone: try c.decodeIfPresent(String.self, forKey: .tel) ?? "")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .n)
        try c.encode(phone, forKey: .tel)
    }
}

/// `t`, `t2`, `n`, `p`, `placeId`, `studioId`, `hallId`, `walk`.
extension RoutePoint: Codable {
    enum CodingKeys: String, CodingKey { case t, t2, n, p, placeId, studioId, hallId, walk }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            start: try c.decodeIfPresent(Int.self, forKey: .t),
            end: try c.decodeIfPresent(Int.self, forKey: .t2),
            name: try c.decodeIfPresent(String.self, forKey: .n) ?? "",
            placeText: try c.decodeIfPresent(String.self, forKey: .p) ?? "",
            spotId: try c.decodeIfPresent(String.self, forKey: .placeId),
            studioId: try c.decodeIfPresent(String.self, forKey: .studioId),
            hallId: try c.decodeIfPresent(String.self, forKey: .hallId),
            walk: try c.decodeIfPresent(Bool.self, forKey: .walk) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(start, forKey: .t)
        try c.encodeIfPresent(end, forKey: .t2)
        try c.encode(name, forKey: .n)
        try c.encode(placeText, forKey: .p)
        try c.encodeIfPresent(spotId, forKey: .placeId)
        try c.encodeIfPresent(studioId, forKey: .studioId)
        try c.encodeIfPresent(hallId, forKey: .hallId)
        try c.encode(walk, forKey: .walk)
    }
}

/// `k`, `path`, `name`, `size`, `url`, `kind`.
extension Attachment: Codable {
    enum CodingKeys: String, CodingKey { case k, path, name, size, url, kind }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            source: try c.decodeLenient(Source.self, forKey: .k, default: .link),
            path: try c.decodeIfPresent(String.self, forKey: .path),
            name: try c.decodeIfPresent(String.self, forKey: .name),
            size: try c.decodeIfPresent(Int.self, forKey: .size),
            url: try c.decodeIfPresent(String.self, forKey: .url),
            kind: try c.decodeLenient(DocKind.self, forKey: .kind)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source.rawValue, forKey: .k)
        try c.encodeIfPresent(path, forKey: .path)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(size, forKey: .size)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeLenient(kind, forKey: .kind)
    }
}

/// `t`, `m`.
extension WishWarning: Codable {
    enum CodingKeys: String, CodingKey { case t, m }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(title: try c.decodeIfPresent(String.self, forKey: .t) ?? "",
                  message: try c.decodeIfPresent(String.self, forKey: .m) ?? "")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .t)
        try c.encode(message, forKey: .m)
    }
}

/// `a`, `b`, `line`.
extension DayMoved: Codable {
    enum CodingKeys: String, CodingKey { case a, b, line }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(start: try c.decode(Int.self, forKey: .a),
                  end: try c.decode(Int.self, forKey: .b),
                  line: try c.decodeIfPresent(String.self, forKey: .line))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .a)
        try c.encode(end, forKey: .b)
        try c.encodeIfPresent(line, forKey: .line)
    }
}

/// `f`, `tel`, `n`, `at`.
extension TelLogEntry: Codable {
    enum CodingKeys: String, CodingKey { case f, tel, n, at }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(field: try c.decodeIfPresent(String.self, forKey: .f),
                  phone: try c.decodeIfPresent(String.self, forKey: .tel) ?? "",
                  name: try c.decodeIfPresent(String.self, forKey: .n),
                  retiredAt: try c.decodeIfPresent(String.self, forKey: .at))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(field, forKey: .f)
        try c.encode(phone, forKey: .tel)
        try c.encodeIfPresent(name, forKey: .n)
        try c.encodeIfPresent(retiredAt, forKey: .at)
    }
}

/// `id`, `status`, `newEnd`.
extension RentRequest: Codable {
    enum CodingKeys: String, CodingKey { case id, status, newEnd }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  status: try c.decodeLenient(Status.self, forKey: .status),
                  newEnd: try c.decodeIfPresent(String.self, forKey: .newEnd))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeLenient(status, forKey: .status)
        try c.encodeIfPresent(newEnd, forKey: .newEnd)
    }
}
