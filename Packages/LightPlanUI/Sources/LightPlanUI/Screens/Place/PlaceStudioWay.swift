import SwiftUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Путь «Фотостудия» листа «Где снимаем» (веб `#wayStudio`, `renderStudios`,
/// `studioRow`, `renderStudioCard`): строка выбирает студию, карандаш раскрывает
/// её карточку под строкой, «Новая студия» — под собой. Выбор ложится в точку
/// только на «Готово» (`studioFromDraft`) — список не меняется под пальцем.
struct PlaceStudioWay: View {
    @Bindable var app: AppModel
    /// Выбранная или правимая студия (веб `studioDraft`).
    @Binding var draft: StudioDraft?
    /// Чья карточка раскрыта: id студии, `newCard` у заводимой, `nil` — ничья (веб `studioEdit`).
    @Binding var edit: String?
    @State private var query = ""
    @FocusState private var focus: Field?
    @Environment(\.colorScheme) private var scheme

    enum Field: Hashable { case query, name, address, phone, hall(String) }
    static let newCard = "new"
    /// Поиск появляется, когда студий больше шести (веб `STUDIO_FIND_FROM`).
    static let findFrom = 6

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let all = app.studios + app.lostStudios
        let many = all.count > Self.findFrom
        let q = many ? query.trimmingCharacters(in: .whitespaces).lowercased() : ""
        let hit = q.isEmpty ? all : all.filter { Self.hit($0, q) }
        let town = sheetCity
        let other = hit.filter { st in !town.isEmpty && !st.town.isEmpty && !Self.sameCity(st.town, town) }
        let here = hit.filter { st in !other.contains(where: { $0.id == st.id }) }
        VStack(alignment: .leading, spacing: 0) {
            if many { search(t, pal).padding(.top, 10) }
            if !here.isEmpty {
                secLabel(t.t("loc.studios"), pal)
                list(here, town: town, t, pal)
            }
            if !other.isEmpty {
                secLabel(t.t("loc.otherCities"), pal)
                list(other, town: town, t, pal)
            }
            if !q.isEmpty && hit.isEmpty {
                Text(t.t("loc.studioNoHit")).font(.system(size: 12)).foregroundStyle(pal.ink6)
                    .padding(.top, 14).padding(.bottom, 12)
            }
            if all.isEmpty && edit != Self.newCard {
                Text(t.t("loc.noStudios")).font(.system(size: 12)).foregroundStyle(pal.ink6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14).padding(.bottom, 4)
            }
            Button { newCard() } label: {
                HStack(spacing: 9) {
                    Icon("plus", size: 17, line: 1.8)
                    Text(t.t("loc.studioNew")).font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(pal.brass)
                .padding(.vertical, 13).padding(.horizontal, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .shotNode("loc.studioNew")
            if edit == Self.newCard { card(t, pal) }
        }
    }

    /// Город, которым список делится надвое (веб `sheetCity`): у точки — город съёмки.
    private var sheetCity: String {
        let town = app.form?.sessionPlace.town ?? ""
        return town.isEmpty ? app.homeCityName : town
    }

    static func sameCity(_ a: String, _ b: String) -> Bool {
        let x = EventForm.cityNorm(a), y = EventForm.cityNorm(b)
        return !x.isEmpty && x == y
    }

    /// Поиск по названию, адресу, городу и залам (веб `studioHit`).
    static func hit(_ st: Studio, _ q: String) -> Bool {
        [st.name, st.address, st.town, st.halls.map(\.name).joined(separator: " ")]
            .joined(separator: " ").lowercased().contains(q)
    }

    // MARK: - Список

    private func secLabel(_ s: String, _ pal: Palette) -> some View {
        Text(s).font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
            .foregroundStyle(pal.ink7)
            .padding(.top, 30).padding(.bottom, 8)
    }

    private func list(_ items: [Studio], town: String, _ t: Lexicon, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items, id: \.id) { st in
                row(st, town: town, t, pal)
                if edit == st.id { card(t, pal).padding(.bottom, 6) }
            }
        }
    }

    private func row(_ st: Studio, town: String, _ t: Lexicon, _ pal: Palette) -> some View {
        let lost = !app.studios.contains { $0.id == st.id }
        let picked = draft?.id == st.id
        let halls = st.halls.map(\.name).filter { !$0.isEmpty }.joined(separator: " · ")
        // В чужом городе подпись называет город, а не залы: важнее «где».
        let sub = !st.town.isEmpty && !town.isEmpty && !Self.sameCity(st.town, town) ? st.town : halls
        let idx = app.studios.firstIndex { $0.id == st.id } ?? -1
        return HStack(spacing: 10) {
            Button { pick(st) } label: {
                HStack(spacing: 10) {
                    Icon("check", size: 15, line: 2.2).foregroundStyle(pal.brass).opacity(picked ? 1 : 0)
                        .frame(width: 17)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(st.name.isEmpty ? t.t("loc.wayStudio") : st.name).font(.system(size: 15))
                            .foregroundStyle(picked ? pal.brass : pal.ink).lineLimit(1)
                        if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundStyle(pal.ink4).lineLimit(1) }
                        if !st.address.isEmpty { Text(st.address).font(.system(size: 12)).foregroundStyle(pal.ink4).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .shotNode(idx >= 0 ? "loc.studio.\(idx)" : "")
            if !lost {
                Button { toggleEdit(st) } label: {
                    PlaceGlyphView(glyph: .pencil, size: 16, line: 1.6)
                        .foregroundStyle(edit == st.id ? pal.brass : pal.ink6)
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.t("loc.editAria"))
                Button {
                    if draft?.id == st.id { draft = nil; edit = nil }
                    app.removeStudio(id: st.id)
                } label: {
                    Icon("trash", size: 16, line: 1.6).foregroundStyle(pal.ink6)
                        .frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.t("loc.delAria"))
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair).frame(height: 1) }
        .padding(.bottom, 1)
    }

    /// Поиск (`.loc-search`): тот же вид, что у поиска мест.
    private func search(_ t: Lexicon, _ pal: Palette) -> some View {
        HStack(spacing: 10) {
            PlaceGlyphView(glyph: .search, size: 17, line: 1.8).foregroundStyle(pal.ink6)
            TextField("", text: $query, prompt: Text(t.t("loc.studioFindPh")).foregroundStyle(pal.ink8))
                .font(.system(size: 16)).foregroundStyle(pal.ink)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focus, equals: .query)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(focus == .query ? pal.press : .clear))
        .shotNode("loc.studioFind")
    }

    // MARK: - Карточка

    /// Название, адрес, телефон, залы (веб `#locStudioCard`) и пояснение про номер.
    private func card(_ t: Lexicon, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                field(t.t("loc.studioNamePh"), \.name, .name, pal)
                field(t.t("loc.addrPh"), \.address, .address, pal).overlay(alignment: .top) { slit(pal) }
                field(t.t("loc.studioTel"), \.phone, .phone, pal).overlay(alignment: .top) { slit(pal) }
                HStack {
                    Text(t.t("loc.halls")).font(.system(size: 15)).foregroundStyle(pal.ink)
                    Spacer(minLength: 0)
                    Button { addHall() } label: {
                        Text(t.t("loc.hallAdd")).font(.system(size: 13, weight: .semibold)).foregroundStyle(pal.brass)
                            .padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .shotNode("loc.hallAdd")
                }
                .padding(.top, 13).padding(.horizontal, 15).padding(.bottom, 9)
                .overlay(alignment: .top) { slit(pal) }
                halls(t, pal)
            }
            // Подложки `--sheet` нет: лист лежит на стекле, цвет листа был бы заплаткой (как «Имя места»).
            .shotNode("loc.studioCard")
            Text(t.t("loc.studioTelNote")).font(.system(size: 12)).foregroundStyle(pal.ink6)
                .lineSpacing(12 * 0.5 - 2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.top, 14)
        .onChange(of: focus) { old, _ in
            if old == .address { Task { await geocodeAddress() } }
        }
    }

    private func slit(_ pal: Palette) -> some View { Rectangle().fill(pal.surface).frame(height: 1) }

    private func field(_ ph: String, _ key: WritableKeyPath<StudioDraft, String>, _ f: Field, _ pal: Palette) -> some View {
        TextField("", text: Binding(get: { draft?[keyPath: key] ?? "" }, set: { draft?[keyPath: key] = $0 }),
                  prompt: Text(ph).foregroundStyle(pal.ink8))
            .font(.system(size: 16)).foregroundStyle(pal.ink)
            .textFieldStyle(.plain)
            .focused($focus, equals: f)
            .onSubmit { if f == .address { Task { await geocodeAddress() } } }
            #if os(iOS)
            .keyboardType(f == .phone ? .phonePad : .default)
            .textContentType(f == .phone ? .telephoneNumber : nil)
            #endif
            .padding(15)
            .frame(height: 48)
    }

    @ViewBuilder
    private func halls(_ t: Lexicon, _ pal: Palette) -> some View {
        let list = draft?.halls ?? []
        if list.isEmpty {
            Text(t.t("loc.hallsNote")).font(.system(size: 12)).foregroundStyle(pal.ink6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15).padding(.bottom, 12)
        } else {
            ForEach(list) { h in
                HStack(spacing: 6) {
                    TextField("", text: Binding(get: { draft?.halls.first { $0.id == h.id }?.name ?? "" }, set: { v in
                        if let i = draft?.halls.firstIndex(where: { $0.id == h.id }) { draft?.halls[i].name = v }
                    }), prompt: Text(t.t("loc.hallNewPh")).foregroundStyle(pal.ink8))
                        .font(.system(size: 14)).foregroundStyle(pal.ink)
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .hall(h.id))
                        .padding(10)
                        .background(pal.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button { draft?.halls.removeAll { $0.id == h.id } } label: {
                        PlaceGlyphView(glyph: .cross, size: 14, line: 1.9).foregroundStyle(pal.ink6)
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.t("loc.hallDel"))
                }
                .padding(.horizontal, 15).padding(.bottom, 10)
            }
        }
    }

    // MARK: - Действия

    /// «Новая студия» (веб `newStudioCard`): город — съёмки, в которой её заводят.
    private func newCard() {
        let town = app.form?.sessionPlace.town ?? ""
        draft = StudioDraft(new: town.isEmpty ? app.homeCityName : town, at: app.place.coordinate)
        edit = Self.newCard
        focus = .name
    }

    /// Тап по строке выбирает студию — и только (веб `pickStudio`).
    private func pick(_ st: Studio) {
        draft = StudioDraft(st, fallback: app.place.coordinate)
        edit = nil
    }

    /// Карандаш раскрывает карточку под строкой; второй тап закрывает (веб `toggleStudioEdit`).
    private func toggleEdit(_ st: Studio) {
        if edit == st.id { edit = nil; return }
        draft = StudioDraft(st, fallback: app.place.coordinate)
        edit = st.id
    }

    private func addHall() {
        guard draft != nil else { return }
        let id = "h" + String(Int64(Date().timeIntervalSince1970 * 1000), radix: 36)
        draft?.halls.append(.init(id: id, name: ""))
        focus = .hall(id)
    }

    /// Координаты студии знает адрес (веб `#locStudioAddr` `change`): ищем его в
    /// городе съёмки — «Красноармейская, 101а» есть и в Томске, и в Москве.
    private func geocodeAddress() async {
        guard let d = draft else { return }
        let q = d.address.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let full = [q, sheetCity].filter { !$0.isEmpty }.joined(separator: ", ")
        guard full != d.addressAsked else { return }
        draft?.addressAsked = full
        guard let h = try? await app.placeSearch.places(matching: full).first,
              draft?.addressAsked == full else { return }
        draft?.latitude = h.coordinate.latitude
        draft?.longitude = h.coordinate.longitude
        // Город студии знает сам адрес: первая часть области ответа — населённый пункт.
        if let town = h.area.split(separator: ",").first.map({ $0.trimmingCharacters(in: .whitespaces) }), !town.isEmpty {
            draft?.town = town
        }
    }
}
