import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Сетка жанров формы с уточнениями (веб `renderGenres`, `subDrop`, L26830–26940).
/// Тап по своему же жанру раскрывает уточнения; удержание 0,42 с делает то же с
/// любой плитки, у которой они есть (веб `holdToOpen`, `MB_HOLD`). Панель встаёт
/// в конец ряда, из которого её позвали, а не сразу за плиткой: иначе она рвала
/// бы ряд. Выбранное уточнение занимает саму плитку жанра — «Ньюборн» с
/// младенцем, а не «Портрет» с пометкой.
struct GenreGrid: View {
    @Bindable var app: AppModel
    let form: EventForm
    /// Какой жанр раскрыт — состояние руки, в запись не идёт (веб `subOpenFor`).
    @State private var openFor: Genre?
    @Environment(\.colorScheme) private var scheme

    static let columns = 4

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let list = app.enabledGenres
        let rows = stride(from: 0, to: list.count, by: Self.columns).map { Array(list[$0..<min($0 + Self.columns, list.count)]) }
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.self) { g in tile(g, t) }
                    ForEach(0..<(Self.columns - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                if let g = openFor, rows[r].contains(g) { drop(g, pal, t) }
            }
        }
        .onChange(of: list) { if let g = openFor, !list.contains(g) { openFor = nil } }
    }

    private func tile(_ g: Genre, _ t: Lexicon) -> some View {
        let on = g == form.genre
        let sub = on ? form.subGenre : nil
        let hasSubs = !g.subGenres.isEmpty
        return GenreTile(genre: g, sub: sub, name: sub.map { t.t("sub." + $0.rawValue) } ?? t.t("genre." + g.rawValue),
                         on: on, marker: hasSubs ? (openFor == g ? .open : .closed) : nil) {
            if on { toggle(g) } else { pick(g, nil) }
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.42, maximumDistance: 10).onEnded { _ in
            if hasSubs { toggle(g) }
        })
    }

    /// Панель: первой стоит сама съёмка без уточнения — ею же его и снимают.
    private func drop(_ g: Genre, _ pal: Palette, _ t: Lexicon) -> some View {
        let cells: [SubGenre?] = [nil] + g.subGenres
        let rows = stride(from: 0, to: cells.count, by: Self.columns).map { Array(cells[$0..<min($0 + Self.columns, cells.count)]) }
        return VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        let x = rows[r][i]
                        GenreTile(genre: g, sub: x, name: x.map { t.t("sub." + $0.rawValue) } ?? t.t("genre." + g.rawValue),
                                  on: g == form.genre && form.subGenre == x, marker: nil) { pick(g, x) }
                    }
                    ForEach(0..<(Self.columns - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
        .padding(5)
        .background(pal.press, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 1).padding(.bottom, 3)
        .shotNode("form.subDrop")
        .transition(.opacity)
    }

    private func toggle(_ g: Genre) {
        guard !g.subGenres.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.2)) { openFor = openFor == g ? nil : g }
    }

    private func pick(_ g: Genre, _ x: SubGenre?) {
        openFor = nil
        app.pickFormGenre(g, sub: x)
    }
}

/// Лист «Мои жанры» (веб `#gSheet`): тап по плитке включает и выключает жанр
/// (последний не выключается); ниже — что жанр, открытый в форме, подставляет
/// в новую съёмку: длительность и срок сдачи.
struct GenreSheet: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// Ряд длительностей (веб `GEN_DURS`) и сроков сдачи (веб `DELV_DAYS`).
    static let durations = [30, 60, 90, 120, 180, 240, 360, 480, 600]
    static let deliveryDays = [3, 7, 14, 30, 90]

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let g = app.form?.genre ?? .portrait
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(pal.edge).frame(width: 38, height: 4).frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, 18)
                Text(t.t("form.myGenres")).font(.system(size: 19, weight: .semibold)).tracking(-0.2).foregroundStyle(pal.ink)
                    .shotNode("gen.title")
                Text(t.t("gen.sub")).font(.system(size: 13)).foregroundStyle(pal.ink4).padding(.top, 5)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(Genre.allCases, id: \.self) { x in
                        let on = app.enabledGenres.contains(x)
                        GenreTile(genre: x, name: t.t("genre." + x.rawValue), on: on) { app.toggleGenre(x) }
                            .opacity(on ? 1 : 0.4)
                    }
                }
                .padding(.top, 18)
                .shotNode("gen.list")
                HStack(spacing: 4) {
                    Text(t.t("form.genre"))
                    Text("· " + t.t("genre." + g.rawValue).lowercased())
                }
                .font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(pal.ink7)
                .padding(.top, 22).padding(.horizontal, 4).padding(.bottom, 9)
                FormGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        head(t.t("gen.durDflt"), pal)
                        chips(durationOptions(g, t), selected: app.genreDuration(g).map(String.init) ?? "light", pal) { v in
                            app.setGenreDuration(g, Int(v))
                        }
                    }
                    if GenreProfile(g).spec.delivery {
                        VStack(alignment: .leading, spacing: 0) {
                            head(t.t("gen.delvDflt"), pal)
                            chips(deliveryOptions(g, t), selected: String(app.genreDeliveryDays(g)), pal) { v in
                                if let d = Int(v) { app.setGenreDeliveryDays(g, d) }
                            }
                        }
                    }
                    Text(t.t("gen.dfltNote")).font(.system(size: 12)).foregroundStyle(pal.ink6)
                        .padding(.horizontal, 15).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { dismiss() } label: {
                    Text(t.t("pick.done")).font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.onBrass)
                        .frame(maxWidth: .infinity).padding(16)
                        .background(pal.brass, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            }
            .padding(.horizontal, 24).padding(.bottom, 34)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    /// «По свету» — только там, где оно и есть заводское (у пейзажа длительность считается по окну дня).
    private func durationOptions(_ g: Genre, _ t: Lexicon) -> [(String, String)] {
        let cur = app.genreDuration(g)
        var list = Self.durations
        if let c = cur, !list.contains(c) { list.append(c); list.sort() }
        let head: [(String, String)] = GenreProfile(g).spec.duration == nil ? [(t.t("gen.byLight"), "light")] : []
        return head + list.map { (durationLabel($0, t), String($0)) }
    }

    private func deliveryOptions(_ g: Genre, _ t: Lexicon) -> [(String, String)] {
        var days = Self.deliveryDays
        let d = app.genreDeliveryDays(g)
        if !days.contains(d) { days.append(d); days.sort() }
        return days.map { n in
            (n == 30 ? t.t("set.delvMonth") : n == 90 ? t.t("set.delv3Months") : t.count("unit.dayShort", n), String(n))
        }
    }

    /// Подпись длительности (веб `durLabel`): «30 мин», «1 ч», «1,5 ч».
    private func durationLabel(_ m: Int, _ t: Lexicon) -> String {
        let h = m / 60, mm = m % 60
        if h == 0 { return t.t("dur.minutes", ["m": "\(mm)"]) }
        if mm == 0 { return t.t("dur.hours", ["h": "\(h)", "hourWord": t.word("unit.hour", h)]) }
        return t.t("dur.hoursMins", ["h": "\(h)", "m": "\(mm)"])
    }

    private func head(_ s: String, _ pal: Palette) -> some View {
        Text(s).font(.system(size: 14)).foregroundStyle(pal.ink3)
            .padding(.horizontal, 15).padding(.top, 13).padding(.bottom, 10)
    }

    private func chips(_ options: [(String, String)], selected: String, _ pal: Palette,
                       pick: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].1 == selected
                Button { pick(options[i].1) } label: {
                    Text(options[i].0)
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? pal.brass : pal.ink3)
                        .padding(.vertical, 10).padding(.horizontal, 15)
                        .background(on ? pal.pressBrass : pal.press, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Строка «Повторять …» (`.row.sep.rep-blk`): подпись 16 и переключатель латунью, 51 × 31, как у веба.
struct FormToggleRow: View {
    var node = ""
    let label: String
    let on: Bool
    let change: (Bool) -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette(scheme)
        HStack(spacing: 12) {
            Text(label).font(.system(size: 16)).foregroundStyle(pal.ink)
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { on }, set: change)).labelsHidden().tint(pal.brass)
        }
        .padding(.vertical, 10).padding(.horizontal, 15).frame(minHeight: 52)
        .shotNode(node)
    }
}

/// Веер правила повтора (веб `#repMenu`, `.scope-menu`): от капсулы, по её правому
/// краю; внизу экрана раскрывается вверх. Строки — галочка текущего и имя.
struct RepeatFan: View {
    let lexicon: Lexicon
    let current: RepeatRule?
    let pick: (RepeatRule?) -> Void
    @Environment(\.colorScheme) private var scheme

    static let rules: [RepeatRule?] = [nil] + RepeatRule.allCases.map(Optional.some)

    var body: some View {
        let pal = Palette(scheme)
        VStack(spacing: 0) {
            ForEach(Self.rules.indices, id: \.self) { i in
                let r = Self.rules[i]
                Button { pick(r) } label: {
                    HStack(spacing: 10) {
                        Icon("check", size: 16, line: 2.2).foregroundStyle(pal.brass).opacity(r == current ? 1 : 0)
                        Text(lexicon.t("rep." + (r?.rawValue ?? "never"))).font(webFont(15)).foregroundStyle(pal.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(minWidth: 208, alignment: .leading)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(pal.sheetGlass))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 18)
        .shotNode("form.repMenu")
    }
}

/// Где стоит капсула правила — от неё раскрывается веер.
struct RepeatAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}
