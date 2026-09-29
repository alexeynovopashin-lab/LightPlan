import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

// MARK: - Блоки заказа, «Место и дальше», тревога прогноза (итерация 26, шаг 4)

/// Звено сделки для вида: имя, закрыто ли, первое ли открытое.
struct CardDealLink: Hashable {
    let step: DealStep
    let name: String
    let done: Bool
    let isNext: Bool
}

struct CardDeal: Hashable {
    let caption: String
    let links: [CardDealLink]
}

/// Гонорар (`#cdMoneyBlk`): доход, «− расходы», «предоплата · остаток», чистые.
struct CardMoney: Hashable {
    let income: String
    let expenseNote: String?
    let prepayNote: String?
    let net: String
}

/// Сдача (`#cdDelvBlk`): слова срочности, цвет — по ступени, срок, тумблер.
struct CardDelivery: Hashable {
    let label: String
    let status: DeliveryStatus
    let byDate: String?
    let delivered: Bool
}

struct CardDocRow: Hashable {
    let name: String
    let kind: String
}

struct CardRouteFold: Hashable {
    let title: String
    let sub: String
}

/// Погода плитки места: знак (`clear`, `part`, `cloud`, `rain`), градус, слово.
/// Знака нет — прогноз ещё в пути или его нет: прочерки, не выдумка.
struct CardPaneWeather: Hashable {
    let sky: String?
    let temp: String
    let word: String
}

/// Плитка «Места и дальше» (`renderPanes`).
struct CardPane: Hashable {
    enum Kind: Hashable { case place, next, guests, breed, trip, gear }
    let kind: Kind
    let icon: String
    /// Мелкая подпись `pn-k`.
    var label: String? = nil
    /// Строка `pn-t`.
    var title: String? = nil
    /// Число `pn-v`.
    var value: String? = nil
    /// Мелкая строка `pn-s`: город под местом, «через 2 ч · 13:00» у «Дальше».
    var sub: String? = nil
    /// Час «Дальше» — латунью внутри `sub`.
    var at: String? = nil
    var wide = false
    var weather: CardPaneWeather? = nil
}

/// Тревога «прогноз переменился» (`#cdShift`): заголовок и слова.
struct CardShift: Hashable {
    let title: String
    let text: String
}

extension AppModel {

    // MARK: Сделка

    func cardDeal(_ s: Session) -> CardDeal? {
        guard DealChain.isShown(genre: s.genre, practice: dealPractice) else { return nil }
        let links = DealChain.links(for: s, practice: dealPractice, among: snapshot.sessions)
        let left = links.filter { !$0.done }
        let caption: String
        if left.isEmpty { caption = lexicon.t("deal.allDone") }
        else if links.contains(where: { $0.partlyPaid == true }) { caption = lexicon.t("dealPrepaid." + dealPractice.rawValue) }
        else if left.count == 1 { caption = lexicon.t("deal.waitOne", ["step": lexicon.t("dealW." + left[0].step.rawValue)]) }
        else { caption = lexicon.t("deal.left", ["n": lexicon.count("deal.step", left.count)]) }
        let next = left.first?.step
        return CardDeal(caption: caption, links: links.map {
            CardDealLink(step: $0.step, name: lexicon.t("dealN." + $0.step.rawValue), done: $0.done, isNext: !$0.done && $0.step == next)
        })
    }

    // MARK: Гонорар и сдача

    private func moneyText(_ v: Decimal, _ s: Session) -> String {
        NumberText(language: language).money(NSDecimalNumber(decimal: v).doubleValue,
                                             Money.currency(of: s, home: settings.currency).rawValue)
    }

    func cardMoney(_ s: Session) -> CardMoney? {
        let income = Money.income(of: s, among: snapshot.sessions)
        guard income > 0 || s.expense > 0 else { return nil }
        let rest = max(0, income - s.prepay)
        return CardMoney(
            income: moneyText(income, s),
            expenseNote: s.expense > 0 ? lexicon.t("pane.minusExp", ["sum": moneyText(s.expense, s)]) : nil,
            prepayNote: s.prepay > 0
                ? lexicon.t("pane.prepayRest", ["word": lexicon.t("prepayW." + dealPractice.rawValue),
                                                "prepay": moneyText(s.prepay, s), "rest": moneyText(rest, s)])
                : nil,
            net: moneyText(income - s.expense, s))
    }

    func cardDelivery(_ s: Session) -> CardDelivery? {
        guard s.kind.isWork, GenreProfile(s.genre).spec.delivery else { return nil }
        let f = PlannerFacts(app: self, dark: false)
        let st = deliveryStatus(s)
        var label = f.deliveryWords(st).label
        if s.delivered, let d = Delivery.daysTaken(s, zone: deviceZone) {
            label = d <= 0 ? lexicon.t("delv.doneSame") : lexicon.t("delv.doneIn", ["days": lexicon.count("unit.day", d)])
        }
        var by: String?
        if !s.delivered, let dd = Delivery.deadline(for: s, setting: snapshot.delivery, prefs: snapshot.genrePrefs) {
            by = lexicon.t("card.byDate", ["d": f.dates.dMon(f.date(dd))])
        }
        return CardDelivery(label: label, status: st, byDate: by, delivered: s.delivered)
    }

    /// Тап по строке сдачи: сдан с датой «сейчас» или снят.
    public func toggleDelivered(id: String) {
        guard let i = snapshot.sessions.firstIndex(where: { $0.id == id }) else { return }
        snapshot.sessions[i].delivered.toggle()
        snapshot.sessions[i].deliveredAt = snapshot.sessions[i].delivered ? now() : nil
        snapshot.sessions[i].modifiedAt = nowMs
        persist()
    }

    // MARK: Задание, модели, документы, маршрут

    func cardModels(_ s: Session) -> [String] {
        s.models.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func cardModelsTitle(_ s: Session) -> String { lexicon.t("pane.models", ["n": "\(cardModels(s).count)"]) }

    func cardDocsCount(_ s: Session) -> String { lexicon.count("unit.doc", s.docs.count) }

    /// Строки списка документов (веб `renderOrderBlocks`): у ссылки имя — хвост
    /// пути, вид — сайт; у файла имя, а вид — расширение и размер.
    func cardDocRows(_ s: Session) -> [CardDocRow] {
        let nt = NumberText(language: language)
        return s.docs.map { d in
            if d.source == .link {
                return CardDocRow(name: DocLabel.sub(d, anyWord: lexicon.t("doc.any")),
                                  kind: DocLabel.host(d.url ?? "", linkWord: lexicon.t("ref.link")))
            }
            var kind = DocLabel.ext(d.name ?? "") ?? lexicon.t("doc.file")
            if let b = d.size, b > 0 {
                kind += " · " + (b < 1_048_576
                    ? lexicon.t("doc.kb", ["n": nt.num(Double(max(1, Int((Double(b) / 1024).rounded()))))])
                    : lexicon.t("doc.mb", ["n": nt.num(Double(b) / 1_048_576, digits: b < 10_485_760 ? 1 : 0)]))
            }
            return CardDocRow(name: DocLabel.sub(d, anyWord: lexicon.t("doc.any")), kind: kind)
        }
    }

    /// Свёрнутая строка маршрута: «7 точек · 11:00 – 23:00» (конец — конец
    /// последней точки, иначе её начало).
    func cardRouteFold(_ s: Session) -> CardRouteFold? {
        let route = s.timedRoute
        guard let first = route.first?.start, let last = route.last else { return nil }
        let f = PlannerFacts(app: self, dark: false)
        let end = last.end ?? last.start ?? first
        return CardRouteFold(title: lexicon.t("card.route"),
                             sub: lexicon.count("unit.point", route.count) + " · " + f.range(Double(first), Double(end)))
    }

    // MARK: Место и дальше

    private func shortPlace(_ p: String) -> String {
        p.split(separator: ",", omittingEmptySubsequences: false).first.map(String.init) ?? ""
    }

    /// Студию называем словом, а не именем: «Фотостудия Томсон» (веб `studioNamed`).
    private func studioSpotName(_ id: String?) -> String {
        guard let id, let st = snapshot.studios.first(where: { $0.id == id }), !st.name.isEmpty else { return "" }
        let word = lexicon.t("studio.tileOnly", ["name": ""]).trimmingCharacters(in: .whitespaces)
        if !word.isEmpty && st.name.lowercased().contains(word.lowercased()) { return st.name }
        return lexicon.t("studio.tileOnly", ["name": st.name])
    }

    /// О каком месте говорит плитка (веб `cardSpot`): у дня с маршрутом — точка,
    /// что идёт сейчас по часам места (до дня — первая), без маршрута — место записи.
    private func cardSpot(_ s: Session) -> (name: String, t: Int, at: GeoPoint?) {
        let route = DayTileText.route(of: s)
        let anchorPoint = anchor(s)
        if !route.isEmpty {
            let i = DayTileText.current(route, nowMinute(of: s))
            let r = route[i >= 0 ? i : 0]
            let stop = Stops.place(of: r, spots: snapshot.spots, studios: snapshot.studios)
            var name = studioSpotName(r.studioId)
            if name.isEmpty { name = shortPlace(stop?.name ?? (r.placeText.isEmpty ? r.name : r.placeText)) }
            if name.isEmpty { name = shortPlace(s.placeText) }
            return (name, r.start ?? s.start, stop?.point ?? anchorPoint)
        }
        var name = studioSpotName(s.studioId)
        if name.isEmpty { name = shortPlace(s.placeText) }
        if name.isEmpty { name = homeCityName }
        return (name, s.start, anchorPoint)
    }

    private func paneWeather(_ s: Session, at p: GeoPoint?, t: Int) -> CardPaneWeather? {
        guard let p else { return nil }
        let k = t >= 0 ? t / 1440 : -((-t + 1439) / 1440)
        let date = s.date(ofDay: k)
        guard let (day, hours) = pointDay(p, date) else { return CardPaneWeather(sky: nil, temp: "—", word: "—") }
        let wall = wallNow(at: s)
        let h = wall.day == date ? wall.minutes / 60 : min(23, max(0, Int((Double(t - k * 1440) / 60).rounded())))
        let c = Weather.nearHour(hours, h)?.temperature ?? Double(day.temperatureBase)
        let deg = Int((settings.tempUnit == .f ? c * 9 / 5 + 32 : c).rounded())
        let sky: String
        switch day.quality {
        case .poor: sky = "rain"
        case .fog: sky = "cloud"
        case .good: sky = "part"
        default: sky = "clear"
        }
        return CardPaneWeather(sky: sky, temp: "\(deg)°", word: lexicon.t("qualCond." + day.quality.rawValue))
    }

    /// Следующая точка сегодня по часам места (веб `nextPoint`).
    private func cardNext(_ s: Session, phase: EventPhase) -> CardPane? {
        let route = DayTileText.route(of: s)
        guard phase != .after, !route.isEmpty else { return nil }
        let wall = wallNow(at: s)
        guard wall.day == s.day, let r = route.first(where: { ($0.start ?? .min) > wall.minutes }), let t = r.start else { return nil }
        let f = PlannerFacts(app: self, dark: false)
        let stop = Stops.place(of: r, spots: snapshot.spots, studios: snapshot.studios)
        let icon = PointSign.name(for: r.name, place: r.placeText.isEmpty ? stop?.name : r.placeText,
                                  studio: !(r.studioId ?? "").isEmpty)
        return CardPane(kind: .next, icon: icon, label: lexicon.t("pane.next"), title: r.name,
                        sub: lexicon.t("pane.inAt", ["in": f.durLabel(t - wall.minutes), "t": f.fmt(Double(t))]),
                        at: f.fmt(Double(t)))
    }

    /// Плитки блока «Место и дальше»: место (во всю ширину), дальше, гости,
    /// порода, выезд, оборудование; нечётная половинка растягивается на ряд.
    func cardPanes(_ s: Session, phase: EventPhase) -> [CardPane] {
        var out: [CardPane] = []
        let spot = cardSpot(s)
        if phase != .after, !spot.name.isEmpty {
            let city = s.placeTown.isEmpty ? homeCityName : s.placeTown
            out.append(CardPane(kind: .place, icon: "pin", title: spot.name, sub: !city.isEmpty && city != spot.name ? city : nil,
                                wide: true, weather: paneWeather(s, at: spot.at, t: spot.t)))
        }
        if let n = cardNext(s, phase: phase) { out.append(n) }
        if s.guests > 0 { out.append(CardPane(kind: .guests, icon: "guests", label: lexicon.t("pane.guests"), value: "\(s.guests)")) }
        if !s.breed.isEmpty { out.append(CardPane(kind: .breed, icon: "paw", label: lexicon.t("pane.breed"), title: s.breed)) }
        if s.trip {
            out.append(CardPane(kind: .trip, icon: "car", label: lexicon.t("pane.trip"),
                                title: s.tripPlace.isEmpty ? lexicon.t("pane.tripAny") : s.tripPlace))
        }
        if !s.gear.isEmpty { out.append(CardPane(kind: .gear, icon: "camera", label: lexicon.t("form.kit"), value: "\(s.gear.count)")) }
        let halves = out.indices.filter { !out[$0].wide }
        if halves.count % 2 == 1, let last = halves.last { out[last].wide = true }
        return out
    }

    // MARK: Тревога «прогноз переменился»

    /// Прогноз якоря съёмки на её день, каким он сейчас (веб `wxSnap`); нет
    /// настоящего прогноза — нет и снимка.
    func cardSkySnap(_ s: Session) -> SkySnap? {
        guard let d = pointDay(anchor(s), s.day)?.day else { return nil }
        return SkySnap(quality: d.quality, sunset: d.sunset)
    }

    /// Уведомления включены (веб `notifOn`): главный тумблер и свой; чего нет в
    /// файле — включено.
    func notifOn(_ kind: String) -> Bool {
        guard case .object(let o)? = snapshot.extra["notif"] else { return true }
        func flag(_ k: String) -> Bool { if case .bool(let b)? = o[k] { return b }; return true }
        return flag("all") && flag(kind)
    }

    private func skyMemory(_ key: String) -> [String: JSONValue] {
        if case .object(let o)? = snapshot.extra[key] { return o }
        return [:]
    }

    private func decodeSky(_ v: JSONValue?) -> SkySnap? {
        guard case .object(let o)? = v, case .string(let q)? = o["q"], let quality = DayQuality(rawValue: q) else { return nil }
        if case .number(let n)? = o["sc"] { return SkySnap(quality: quality, sunset: Int(n)) }
        return SkySnap(quality: quality, sunset: nil)
    }

    private func encodeSky(_ s: SkySnap) -> JSONValue {
        .object(["q": .string(s.quality.rawValue), "sc": s.sunset.map { .number(Double($0)) } ?? .null])
    }

    /// Строка о переменившемся прогнозе: держится на `wxSeen`, гаснет, когда
    /// карточку закрыли. Выключенные уведомления гасят и её; после съёмки молчит.
    func cardShift(_ s: Session, phase: EventPhase) -> CardShift? {
        guard phase != .after, notifOn("wx"), let now = cardSkySnap(s),
              let was = decodeSky(skyMemory("wxSeen")[s.id]), WeatherShift.gap(was, now) > 0 else { return nil }
        let title = WeatherShift.isUp(was, now) ? "wxs.upT" : WeatherShift.gap(was, now) == 3 ? "wxs.badT" : "wxs.downT"
        let text: String
        if WeatherShift.saysScore(was, now) {
            text = lexicon.t("wxs.scoreM", ["a": "\(was.sunset ?? 0)", "b": "\(now.sunset ?? 0)"])
        } else {
            text = lexicon.t("wxs.skyM", ["a": lexicon.t("qualCond." + was.quality.rawValue).lowercased(),
                                           "b": lexicon.t("qualCond." + now.quality.rawValue).lowercased()])
        }
        return CardShift(title: lexicon.t(title), text: text)
    }

    /// Карточку закрыли — числа прочитаны, и следующее сравнение идёт от них
    /// (веб `wxAck`). Ничего не менялось и не говорили — ничего не пишется.
    func acknowledgeForecast(_ s: Session) {
        guard let now = cardSkySnap(s) else { return }
        let seen = skyMemory("wxSeen"), told = skyMemory("wxTold")
        if told[s.id] == nil, let was = decodeSky(seen[s.id]), WeatherShift.gap(was, now) == 0 { return }
        var newTold = told
        newTold[s.id] = nil
        var newSeen = seen
        newSeen[s.id] = encodeSky(now)
        snapshot.extra["wxTold"] = .object(newTold)
        snapshot.extra["wxSeen"] = .object(newSeen)
        persist()
    }
}
