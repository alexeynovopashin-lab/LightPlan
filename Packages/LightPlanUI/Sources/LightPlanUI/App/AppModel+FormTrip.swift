import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Хвосты места в форме (итерация 24, шаг 4б): выезд, время в пути, связь с
/// бронью, поиск города, наложения в плашке, студии листа «Где снимаем».
extension AppModel {

    /// Родной город фотографа (веб `myCity()`, `me.city`).
    public var homeCityName: String { settings.home.name.trimmingCharacters(in: .whitespaces) }

    // MARK: - Выезд и дорога

    public func setFormTrip(_ on: Bool) {
        editForm { $0.setTrip(on) }
        // Включили выезд, а дороги рядом нет — сразу лист «Занять время» (веб `fTripToggle`).
        if on, let f = form, EventForm.roadBlocks(near: f.day, in: snapshot.blocks).isEmpty { openRoadSheet() }
    }

    /// Строка «Время в пути» (веб `renderRoadRow`): значение и подпись.
    public func formRoadRow(_ f: EventForm) -> (value: String, note: String, set: Bool) {
        let near = EventForm.roadBlocks(near: f.day, in: snapshot.blocks)
        guard !near.isEmpty else { return (lexicon.t("form.roadAdd"), lexicon.t("form.roadNoteOff"), false) }
        let dt = DateText(language: language)
        let v = near.map { b -> String in
            var c = DateComponents()
            (c.year, c.month, c.day, c.hour) = (b.from.year, b.from.month, b.from.day, 12)
            let at = Calendar(identifier: .gregorian).date(from: c) ?? Date()
            return dt.dMonShortYear(at) + " · " + lexicon.t("blkKind." + b.kind.rawValue)
        }.joined(separator: " · ")
        return (v, lexicon.t("form.roadNoteOn"), true)
    }

    /// «Время в пути» (веб `openRoadSheet`): дорога рядом есть — она на правку;
    /// нет — новая «Дорога» или «Перелёт» с утра, откуда — родной город, куда — место съёмки.
    public func openRoadSheet() {
        guard let f = form else { return }
        if let b = EventForm.roadBlocks(near: f.day, in: snapshot.blocks).first { openBlockSheet(editing: b.id); return }
        let from = settings.home.coordinate ?? place.coordinate
        let to = f.sessionPlace.latitude.flatMap { la in f.sessionPlace.longitude.map { GeoCoordinate(latitude: la, longitude: $0) } }
        let flight = settings.home.coordinate != nil && to.map { Self.km(from, $0) > 700 } == true
        var b = Block(id: Self.newBlockId(nowMs), kind: flight ? .flight : .road, from: f.day)
        b.note = f.sessionPlace.town
        b.allDay = false
        b.days = 1
        b.start = 540
        // Дорогу приложение не спрашивает (OSRM не перенесён) — два часа, как у веба без ответа сети.
        b.duration = flight ? 240 : 120
        let zFrom = place.zones.utcOffsetHours(latitude: from.latitude, longitude: from.longitude, on: f.day)
        b.zoneFrom = zFrom
        b.zoneTo = to.map { place.zones.utcOffsetHours(latitude: $0.latitude, longitude: $0.longitude, on: f.day) } ?? zFrom
        blockSheet = BlockDraft(block: b, editing: false)
    }

    /// Расстояние по дуге (веб `kmBetween`).
    static func km(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        let r = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * r, dLon = (b.longitude - a.longitude) * r
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * r) * cos(b.latitude * r) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * 6371 * asin(min(1, h.squareRoot()))
    }

    // MARK: - Город

    /// Набор города кончился (веб `#fCity` `blur` + `change`): первая буква заглавная;
    /// пока точки нет — координаты едут за городом, иначе свет считается в прежнем.
    public func commitFormCity() async {
        guard var f = form else { return }
        let q = HomeCity.cap(f.sessionPlace.town)
        if q != f.sessionPlace.town { f.sessionPlace.town = q; form = f; formChanged() }
        guard !q.isEmpty, f.sessionPlace.name.trimmingCharacters(in: .whitespaces).isEmpty,
              q != formCityAsked else { return }
        formCityAsked = q                      // за один и тот же город не спрашиваем дважды
        let hits = try? await cityLookup.cities(matching: q)
        // Сбой сети — не ответ: тот же город можно спросить снова (ревью GPT к 9099202; веб так не умеет).
        if hits == nil, formCityAsked == q { formCityAsked = nil }
        guard let hit = hits?.first, var now = form, now.id == f.id,
              now.sessionPlace.town == q, now.sessionPlace.name.isEmpty else { return }
        now.sessionPlace.latitude = hit.coordinate.latitude
        now.sessionPlace.longitude = hit.coordinate.longitude
        form = now
        formChanged()
    }

    // MARK: - Бронь

    /// Строка «Связать с бронью» (веб `renderLinkRow`): видна только у студии первой точки с ключом.
    public func formLinkShown(_ f: EventForm) -> Bool { f.linkStudio(studios: snapshot.studios) != nil }

    /// Номера съёмки, какие приложение знает (веб `shootPhones`): свой, клиента, заказа, людей.
    func shootPhones(_ f: EventForm) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for v in [myPhone, f.clientPhone, f.orderPhone] + f.persons.map(\.phone) {
            let d = TelFormat.full(v, country: telCountry)
            if !d.isEmpty, seen.insert(d).inserted { out.append(d) }
        }
        return out
    }

    /// Тап по «Связать с бронью»: ответ — ключ подписи («бронь найдена» и т. п.).
    public func linkFormBooking() async -> String {
        guard let f = form, let st = f.linkStudio(studios: snapshot.studios), let r = f.route.first else { return "form.linkAsk" }
        let phones = shootPhones(f)
        guard !phones.isEmpty else { return "form.linkNone" }
        // Дата и часы — самой ячейки (веб: бронь считается по своему началу); не назвали — съёмки.
        let from = r.start ?? f.start, to = r.end ?? (f.start + f.duration)
        let dayOff = Int((Double(from) / 1440).rounded(.down))
        let day = f.day.adding(days: dayOff)
        let q = BookingQuery(studioKey: st.key, catalogId: st.catalogId,
                             date: String(format: "%04d-%02d-%02d", day.year, day.month, day.day),
                             from: Self.hm24(from), to: Self.hm24(to), phones: phones)
        // Пока студия думала, форму могли закрыть, открыть другую, сменить студию, день
        // или часы: ответ ложится только туда, о чём спрашивали (ревью GPT к 9099202, 5ea8dd2).
        func same() -> Bool {
            guard let now = form, let h = now.route.first else { return false }
            return now.id == f.id && h.studioId == st.id && now.day == f.day && now.start == f.start
                && now.duration == f.duration && h.start == r.start && h.end == r.end
        }
        do {
            guard let a = try await bookingMatch.match(q) else {
                if same() { editForm { $0.bookingRef = nil } }
                return "form.linkNone"
            }
            guard same() else { return "form.linkAsk" }
            let base = dayOff * 1440
            editForm {
                $0.applyBooking(ref: a.ref, hallId: a.hallId, start: a.start.flatMap(Self.minutes).map { $0 + base },
                                end: a.end.flatMap(Self.minutes).map { $0 + base },
                                label: { [lexicon] in lexicon.t("form.placeHall", ["place": $0, "hall": $1]) },
                                spots: snapshot.spots, studios: snapshot.studios)
            }
            return "form.linked"
        } catch {
            // Студия не ответила — это не «брони нет»: прежняя связь остаётся. Веб её
            // здесь стирает (`fBookingRef = null`); расхождение — DECISIONS, шаг 4б.
            return "form.linkOff"
        }
    }

    static func hm24(_ m: Int) -> String {
        let x = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", x / 60, x % 60)
    }

    static func minutes(_ hm: String) -> Int? {
        let p = hm.split(separator: ":")
        guard p.count >= 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return h * 60 + m
    }

    // MARK: - Наложения

    /// Плашка вверху формы (веб `refreshForm`): наложение важнее погоды — первое
    /// из самых тяжёлых, иначе «замысел против прогноза».
    public func formWarning(_ f: EventForm) -> WishWarning? {
        formClashWarning(f) ?? formWishWarning(f)
    }

    /// Первое наложение словами (веб `clashesFor(…)[0]`). Дороги приложение не
    /// знает — «впритык» считается по порогу фотографа, как у веба без сети.
    public func formClashWarning(_ f: EventForm) -> WishWarning? {
        let probe = f.session(orgName: nil, and: "", studios: snapshot.studios, spots: snapshot.spots,
                              homeCity: homeCityName, now: now())
        let trip = f.mode != .meet && f.trip(home: homeCityName)
        let c = ClashCandidate(day: f.day, start: f.start, end: f.start + f.duration, placeKey: probe.placeKey,
                               skipIndex: snapshot.sessions.firstIndex { $0.id == f.id }, wishes: f.wishes,
                               point: GeoPoint(f.sessionPlace.latitude, f.sessionPlace.longitude),
                               trip: trip, tripOff: f.tripManual && !trip)
        guard let first = Overlaps.clashes(for: c, sessions: snapshot.sessions, blocks: snapshot.blocks,
                                           context: clashContext).first else { return nil }
        return clashWords(first)
    }

    /// Слова наложения (`clash.*T` / `clash.*M` веба).
    func clashWords(_ c: Clash) -> WishWarning {
        let facts = PlannerFacts(app: self, dark: false)
        let k = c.kind.rawValue
        let name: String, when: String, placeLine: String
        switch c.subject {
        case .block(let i):
            name = facts.blockLabel(snapshot.blocks[i])
            when = facts.range(c.from.map(Double.init), c.to.map(Double.init))
            placeLine = ""
        case .session(let i):
            let s = snapshot.sessions[i]
            let n = facts.words.clientName(s)
            name = n.isEmpty ? facts.words.typeName(s) : n
            when = facts.range(c.from.map(Double.init), c.to.map(Double.init))
            let pt = s.place.isEmpty ? s.placeTown : s.place
            placeLine = [pt, !s.place.isEmpty && !s.placeTown.isEmpty ? s.placeTown : ""].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        var p = ["name": name, "when": when, "place": placeLine]
        if let m = c.travel { p["need"] = facts.durLabel(m) }
        if let g = c.gap { p["gap"] = facts.durLabel(g); p["have"] = facts.durLabel(g) }
        return WishWarning(title: lexicon.t("clash." + k + "T"), message: lexicon.t("clash." + k + "M", p))
    }

    // MARK: - Студии

    /// Студия из карточки листа (веб `studioFromDraft`): прежняя правится на месте,
    /// новая встаёт первой. Пустые залы выбрасываются.
    @discardableResult
    func saveStudio(_ d: StudioDraft) -> Studio {
        let lat = d.latitude ?? place.coordinate.latitude, lon = d.longitude ?? place.coordinate.longitude
        var st = snapshot.studios.first { $0.id == d.id } ?? Studio(id: Self.newStudioId(now()), latitude: lat, longitude: lon)
        let name = d.name.trimmingCharacters(in: .whitespaces)
        st.name = name.isEmpty ? (st.name.isEmpty ? GeoCoordinate(latitude: lat, longitude: lon).text : st.name) : name
        st.address = d.address.trimmingCharacters(in: .whitespaces)
        st.phone = d.phone.trimmingCharacters(in: .whitespaces)
        st.key = d.key
        st.catalogId = d.catalogId
        // Город формы наследуется, только пока речь об одном городе: дальше 60 км — свой.
        var far = false
        if let fl = form?.sessionPlace.latitude, let fo = form?.sessionPlace.longitude {
            far = Self.km(GeoCoordinate(latitude: fl, longitude: fo), GeoCoordinate(latitude: lat, longitude: lon)) > 60
        }
        let formTown = form?.sessionPlace.town ?? ""
        st.town = !d.town.isEmpty ? d.town : (far ? "" : (formTown.isEmpty ? homeCityName : formTown))
        if st.town.isEmpty { st.town = snapshot.studios.first { $0.id == d.id }?.town ?? "" }
        st.halls = d.halls.compactMap { h in
            let n = h.name.trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? nil : Studio.Hall(id: h.id, name: n)
        }
        st.latitude = (lat * 100_000).rounded() / 100_000
        st.longitude = (lon * 100_000).rounded() / 100_000
        st.modifiedAt = Self.ms(now())
        if let i = snapshot.studios.firstIndex(where: { $0.id == st.id }) {
            snapshot.studios[i] = st
        } else {
            snapshot.studios.insert(st, at: 0)
        }
        persist()
        return st
    }

    /// Убрать студию из списка (веб: крестик строки). Записи её помнят сами.
    public func removeStudio(id: String) {
        snapshot.studios.removeAll { $0.id == id }
        persist()
    }

    /// Студии, которые есть в съёмках, но которых нет в списке (веб `lostStudios`).
    var lostStudios: [Studio] {
        var seen = Set<String>(), out: [Studio] = []
        for s in snapshot.sessions.sorted(by: { ($0.day.ordinal, $0.start) > ($1.day.ordinal, $1.start) }) {
            guard let id = s.studioId, !seen.contains(id), !snapshot.studios.contains(where: { $0.id == id }) else { continue }
            seen.insert(id)
            var st = Studio(id: id, name: s.place.trimmingCharacters(in: .whitespaces), latitude: s.latitude, longitude: s.longitude)
            st.address = s.placeAddress
            st.town = s.placeTown
            out.append(st)
        }
        return out
    }

    /// `newStudioId` веба: «st» + время и четыре знака в base36.
    static func newStudioId(_ now: Date) -> String {
        let tail = String((0..<4).map { _ in "0123456789abcdefghijklmnopqrstuvwxyz".randomElement()! })
        return "st" + String(ms(now), radix: 36) + tail
    }
}

/// Карточка студии в листе, пока «Готово» не нажато (веб `studioDraft`):
/// список студий не меняется под пальцем.
struct StudioDraft: Equatable {
    struct Hall: Equatable, Identifiable { var id: String; var name: String }
    var id: String?
    var name = ""
    var address = ""
    var phone = ""
    var key = ""
    var catalogId: String?
    var town = ""
    var halls: [Hall] = []
    var latitude: Double?
    var longitude: Double?
    /// Адрес, по которому уже спрашивали геокодер (веб `addrAt`).
    var addressAsked: String?

    init(new town: String, at c: GeoCoordinate) {
        self.town = town
        latitude = c.latitude
        longitude = c.longitude
    }

    init(_ st: Studio, fallback c: GeoCoordinate) {
        id = st.id; name = st.name; address = st.address; phone = st.phone; key = st.key
        catalogId = st.catalogId; town = st.town
        halls = st.halls.map { Hall(id: $0.id, name: $0.name) }
        latitude = st.latitude ?? c.latitude
        longitude = st.longitude ?? c.longitude
    }
}
