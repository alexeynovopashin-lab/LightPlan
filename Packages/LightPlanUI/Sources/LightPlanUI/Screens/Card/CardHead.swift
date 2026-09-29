import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Слова шапки карточки (веб `renderEvHead`) — отдельно от вида, чтобы тесты
/// читали их словами.
@MainActor
struct CardHeadText {
    /// Крупно — пара, клиент, организация; нет клиента — жанр словом.
    var name: String
    /// Лицо заказа строкой ниже (группа «Заказчик»).
    var person: String
    /// «Портрет · 23 сентября, завтра · 12:20 – 13:50».
    var when: String
    /// Номер для показа («+7 961 887-80-78») и для набора; нет номера — `nil`.
    var tel: (shown: String, dial: String)?

    init(_ s: Session, phase: EventPhase, app: AppModel) {
        let f = PlannerFacts(app: app, dark: true)
        let w = f.words
        var name = w.clientName(s), person = ""
        if s.profile.groupSpec.order {
            if let id = s.orgId, let org = app.orgs.first(where: { $0.id == id }) {
                // Имя — из организации, не из записи: переименовали — карточка
                // показывает новое.
                if !org.name.isEmpty { name = org.name }
                person = s.orderPerson.isEmpty ? org.person : s.orderPerson
            } else {
                // Запись до организаций: строка делится по «·», «|», «,».
                let parts = name.components(separatedBy: CharacterSet(charactersIn: "·|,"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count > 1 { name = parts[0]; person = parts.dropFirst().joined(separator: ", ") }
            }
        }
        self.name = name.isEmpty ? w.typeName(s) : name
        self.person = person

        // Слово у даты — по дате места съёмки: в Москве 22:30 ещё сегодня,
        // хотя в Томске уже завтра.
        let days = app.wallNow(at: s).day.days(since: s.day)
        let word: String
        if phase == .after {
            word = days <= 0 ? "" : days == 1 ? f.t.t("when.yesterday")
                : days <= 7 ? f.t.t("when.daysAgo", ["n": f.t.count("unit.day", days)]) : ""
        } else {
            word = days == -1 ? f.t.t("when.tomorrow")
                : (-7 ... -2).contains(days) ? f.t.t("when.inDays", ["n": f.t.count("unit.day", -days)]) : ""
        }
        var bits: [String] = []
        switch s.kind {
        case .meet: bits.append(f.t.t("card.meetAbout", ["genre": w.shortType(s).lowercased()]))
        case .event: bits.append(f.t.t("card.eventAbout", ["genre": w.shortType(s).lowercased()]))
        default: if !name.isEmpty { bits.append(w.typeName(s)) }
        }
        let date = f.dates.dMon(f.date(s.day))
        bits.append(Self.nbsp(word.isEmpty ? date : f.t.t("card.dateWhen", ["date": date, "when": word])))
        let end = s.endMinute
        let endDay = Self.day(end, 1440) - Self.day(s.start, 1440)
        bits.append(endDay != 0
            ? Self.nbsp(f.fmt(Double(s.start)) + " – " + f.fmt(Double(end)) + " "
                        + f.dates.dMon(f.date(s.day.adding(days: Self.day(end, 1440)))))
            : f.range(Double(s.start), Double(end)))
        when = bits.joined(separator: "\u{00A0}· ")

        // Номер показываем и набираем только целым: «961 887-80-78» без кода
        // страны набирается лишь из своей области.
        let raw = w.firstPhone(s)
        if raw.isEmpty { tel = nil } else {
            let e = TelFormat.e164(raw, country: app.telCountry)
            tel = (e.isEmpty ? raw : TelFormat.format(e, country: app.telCountry),
                   e.isEmpty ? raw.filter { $0.isNumber || $0 == "+" } : e)
        }
    }

    /// Сутки шкалы съёмки, в которые попадает минута (00:30 вторых — 1).
    static func day(_ m: Int, _ n: Int = 1440) -> Int { Int((Double(m) / Double(n)).rounded(.down)) }

    /// Дата со словом и промежуток через сутки не рвутся внутри: перенос —
    /// только на « · » между частями.
    static func nbsp(_ s: String) -> String {
        String(s.map { $0.isWhitespace ? "\u{00A0}" : $0 })
    }
}

/// Шапка карточки (`#cdEvHead`): знак события, имя, лицо заказа, строка
/// «когда», телефон. Всё по центру.
struct CardHead: View {
    let app: AppModel
    let s: Session
    let phase: EventPhase
    let pal: Palette
    /// Такт карточки: слово «завтра» у даты меняется в полночь.
    let tick: Date
    @Environment(\.openURL) private var openURL

    /// Ступени кегля имени (веб `TITLE_SIZES`): не влезло и в 21 — переносится.
    static let titleSizes: [CGFloat] = [29, 26, 23, 21]

    var body: some View {
        let h = CardHeadText(s, phase: phase, app: app)
        VStack(spacing: 0) {
            sign
            title(h.name).shotNode("card.name").padding(.top, 6)
            if !h.person.isEmpty {
                Text(h.person).font(webFont(14.5)).foregroundStyle(pal.ink2)
                    .shotNode("card.person").padding(.top, 5)
            }
            Text(h.when).font(webFont(13)).foregroundStyle(phase == .after ? pal.ink6 : pal.green)
                .shotNode("card.when").padding(.top, 5)
            if let tel = h.tel { telLink(tel) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    /// Знак уточнения жанра, иначе жанра (веб `typeSvg`), 40×30, линия 1,6;
    /// знак повтора — сбоку, знак жанра остаётся по центру.
    private var sign: some View {
        let w = PlannerWords(lexicon: app.lexicon, orgs: app.orgs)
        return Group {
            if let n = w.iconName(s) { Icon(n, size: 30, line: 1.6) }
            else { Icon(genre: s.genre?.rawValue ?? "", size: 30, line: 1.6) }
        }
        .foregroundStyle(pal.glyph)
        .frame(width: 40, height: 30)
        .overlay(alignment: .topTrailing) {
            if s.repeatInfo != nil {
                Icon("repeat", size: 16).foregroundStyle(pal.ink5)
                    .offset(x: 16 + 5, y: 7)
            }
        }
        .shotNode("card.sign")
    }

    /// Имя одной строкой на самом крупном кегле, какой влезает.
    private func title(_ name: String) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Self.titleSizes, id: \.self) { size in
                line(name, size).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            line(name, Self.titleSizes.last!)
        }
    }

    /// Строка веба — `line-height: 1.1`, у SF своя — 1,19 кегля (пара шага 4:
    /// 34,5 pt на 29): лишнее снимается поровну сверху и снизу, иначе всё ниже
    /// имени уезжает на 2,6 pt. Перенесённое имя идёт шагом SF — у SwiftUI
    /// шаг строк меньше родного не задаётся.
    private func line(_ name: String, _ size: CGFloat) -> some View {
        Text(name).font(webFont(size, 700)).tracking(-0.7).foregroundStyle(pal.ink)
            .padding(.vertical, -size * (1.19 - 1.1) / 2)
    }

    private func telLink(_ tel: (shown: String, dial: String)) -> some View {
        Button { if let u = URL(string: "tel:" + tel.dial) { openURL(u) } } label: {
            HStack(spacing: 7) {
                Text(tel.shown).font(webFont(19)).monospacedDigit()
                Icon("phone", size: 15)
            }
            .foregroundStyle(pal.brass)
            .padding(.horizontal, 10).padding(.vertical, 9)
        }
        .buttonStyle(PressFade())
        .shotNode("card.tel")
        .padding(.top, 4)
    }
}
