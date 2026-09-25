import SwiftUI
import LightPlanCore
import LightPlanDomain
import LightPlanData
import CoreLocation

/// Лист «Где снимаем» (`#locSheet` веба, итерация 21в): кнопка места в шапке
/// «Света» и «Карты». Развилка из двух путей — «Место» (поиск, «Мои места»)
/// и «Геопозиция» (моё место, широта и долгота); со второго экрана «‹ Где
/// снимаем» возвращает на развилку, не закрывая лист. «Готово» переносит
/// место приложения: свет, погода, имя шапки и камера карты едут за ним.
///
/// Вид — прототипа веба (числа — справка 21в и пара `make shots`), лист —
/// системный: в iOS 26 он лежит на встроенном стекле (§ 5.4 плана). Поля,
/// у которых в вебе фон `--sheet` — цвет самого листа, — здесь без фона: на
/// стекле цвет листа был бы непрозрачной заплаткой.
struct PlaceSheet: View {
    @Bindable var app: AppModel
    /// Высота окна — потолок листа 86 % (`max-height: 86vh`).
    let windowHeight: CGFloat

    @Environment(\.colorScheme) private var scheme
    @State private var form: PlaceSheetForm
    @State private var contentHeight: CGFloat = 300
    @State private var query = ""
    @State private var hits: [PlaceHit] = []
    /// Строка вместо ответов: «Ничего не нашлось» или «без сети».
    @State private var hitsNote: String?
    @State private var detecting = false
    /// Строка «Моих мест», раскрытая карандашом.
    @State private var editing: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case query, lat, lon, name, address, spotName, spotAddress }

    init(app: AppModel, windowHeight: CGFloat) {
        self.app = app
        self.windowHeight = windowHeight
        _form = State(initialValue: PlaceSheetForm(here: app.place.coordinate, way: app.placeSheetStart))
    }

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Ручка веба (`.grip`): 38 × 4, 10 от края листа, 18 до текста.
                Capsule().fill(pal.edge).frame(width: 38, height: 4)
                    .shotNode("loc.grip")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, 18)
                header(t, pal)
                switch form.way {
                case .fork: ways(t, pal)
                case .addr: addrWay(t, pal)
                case .geo: geoWay(t, pal)
                }
                if form.way != .fork { placeGroup(t, pal) }
                errorLine(t, pal)
                if form.way != .fork { doneButton(t, pal) }
            }
            .padding(.horizontal, 24)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .shotNode("loc.sheet")
        .presentationDetents([detent])
        .presentationDragIndicator(.hidden)
        .animation(.snappy(duration: 0.3), value: form.way)
        .task {
            // Первый раз: разрешение ещё не спрашивали — лист встаёт на путь
            // координат и спрашивает сам (веб, `openLocSheet`).
            if form.way == .fork, app.locationNeedsPermission {
                form.open(.geo)
                await locate()
            }
        }
    }

    /// Высота по содержимому, не выше 86 % окна — дальше лист прокручивается.
    private var detent: PresentationDetent {
        let cap = windowHeight * 0.86
        return contentHeight > cap ? .height(cap) : .height(contentHeight)
    }

    private func close() { app.placeSheetOpen = false }

    // MARK: - Шапка листа

    /// «‹ Где снимаем» (14, `--ink-4`, 10 под), заголовок 19/650, подпись 13.
    @ViewBuilder
    private func header(_ t: Lexicon, _ pal: Palette) -> some View {
        if form.way != .fork {
            Button { form.open(.fork); hits = []; hitsNote = nil; query = ""; editing = nil } label: {
                HStack(spacing: 6) {
                    Icon("chevron", size: 16, line: 2.4).rotationEffect(.degrees(180))
                    Text(t.t("loc.back")).font(.system(size: 14)).frame(height: 17)
                }
                .foregroundStyle(pal.ink4)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .shotNode("loc.back")
        }
        Text(t.t(form.titleKey))
            .font(webFont(19, 650)).tracking(-0.2)
            .foregroundStyle(pal.ink)
            .frame(height: 22)
            .shotNode("loc.title", text: t.t(form.titleKey))
        Text(t.t(form.subKey))
            .font(.system(size: 13))
            .foregroundStyle(pal.ink4)
            .frame(height: 16)
            .shotNode("loc.sub", text: t.t(form.subKey))
            .padding(.top, 5)
    }

    // MARK: - Развилка

    /// Две строки (`.loc-way`): знак 19, заголовок 16 и подпись 12, шеврон.
    /// «Фотостудии» с шапки нет — месту приложения студия не нужна.
    private func ways(_ t: Lexicon, _ pal: Palette) -> some View {
        VStack(spacing: 0) {
            wayRow(.addr, icon: "city", title: t.t("loc.wayAddr"), sub: t.t("loc.wayAddrSub"), pal)
            wayRow(.geo, icon: "route", title: t.t("loc.wayGeo"), sub: t.t("loc.wayGeoSub"), pal)
        }
        .padding(.top, 16)
    }

    private func wayRow(_ way: PlaceSheetForm.Way, icon: String, title: String, sub: String, _ pal: Palette) -> some View {
        Button { form.open(way) } label: {
            HStack(spacing: 13) {
                Icon(icon, size: 19, line: 1.6).foregroundStyle(pal.ink4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16)).foregroundStyle(pal.ink).frame(height: 19)
                    Text(sub).font(.system(size: 12)).foregroundStyle(pal.ink5).frame(height: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon("chevron", size: 16, line: 2.4).foregroundStyle(pal.ink4)
                    .padding(.trailing, -4).padding(.leading, 2)
            }
            .padding(.vertical, 15).padding(.horizontal, 2)
            .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFade())
        .shotNode("loc.way." + way.rawValue)
    }

    // MARK: - Путь «Место»

    private func addrWay(_ t: Lexicon, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField(t, pal).padding(.top, 10)
            if !hits.isEmpty || hitsNote != nil { hitList(pal).padding(.top, 8) }
            // Лишние 30 — два пустых списка недавних мест веба (`#recentList`,
            // `#recentOtherList`): в режиме места приложения они скрыты, но
            // `display: flex` сильнее `[hidden]`, и их поля 2 + 14 + 14
            // (средние схлопываются) остаются. Замер 21в.
            Text(t.t("loc.myPlaces"))
                .font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(pal.ink7)
                .frame(height: 12)
                .shotNode("loc.spots", text: t.t("loc.myPlaces"))
                .padding(.top, 30 + 30).padding(.bottom, 8)
            spotList(t, pal).padding(.top, 2).padding(.bottom, 14)
        }
    }

    /// Поиск (`.loc-search`): лупа 17 `--ink-6`, поле 16, высота 46.
    private func searchField(_ t: Lexicon, _ pal: Palette) -> some View {
        HStack(spacing: 10) {
            PlaceGlyphView(glyph: .search, size: 17, line: 1.8).foregroundStyle(pal.ink6)
            TextField("", text: $query, prompt: Text(t.t("loc.queryPh")).foregroundStyle(pal.ink8))
                .font(.system(size: 16)).foregroundStyle(pal.ink)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($focus, equals: .query)
                .submitLabel(.search)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(focus == .query ? pal.press : .clear))
        .shotNode("loc.search")
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 3 else { hits = []; hitsNote = nil; return }
            // Пауза веба 450 мс: не спрашивать геокодер на каждую букву.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            do {
                let found = try await app.placeSearch.places(matching: q)
                guard !Task.isCancelled else { return }
                hits = found
                hitsNote = found.isEmpty ? t.t("loc.nothingFound") : nil
            } catch {
                guard !Task.isCancelled else { return }
                // Apple отвечает «не нашёл» ошибкой (`geocodeFoundNoResult`),
                // а не пустым списком; без сети — кодом `network`.
                hits = []
                hitsNote = t.t((error as? CLError)?.code == .network ? "loc.searchOffline" : "loc.nothingFound")
            }
        }
    }

    /// Ответы поиска (`.loc-hit`): имя 15, область 12, не выше 168.
    private func hitList(_ pal: Palette) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let hitsNote {
                    Text(hitsNote).font(.system(size: 13)).foregroundStyle(pal.ink6)
                        .padding(.vertical, 10).padding(.horizontal, 2)
                }
                ForEach(Array(hits.enumerated()), id: \.offset) { i, h in
                    Button {
                        form.pick(h); query = h.name; hits = []; hitsNote = nil; focus = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.name).font(.system(size: 15)).foregroundStyle(pal.ink)
                            if !h.area.isEmpty { Text(h.area).font(.system(size: 12)).foregroundStyle(pal.ink4) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 11).padding(.horizontal, 2)
                        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressFade())
                    .shotNode("loc.hit.\(i)")
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 168)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// «Мои места» (`renderSpots`): тап — переезд и лист закрывается,
    /// карандаш раскрывает имя и адрес под строкой, крестик удаляет.
    @ViewBuilder
    private func spotList(_ t: Lexicon, _ pal: Palette) -> some View {
        if app.spots.isEmpty {
            Text(t.t("loc.emptySheet"))
                .font(.system(size: 12)).foregroundStyle(pal.ink6)
                .fixedSize(horizontal: false, vertical: true)
                .shotNode("loc.empty", text: t.t("loc.emptySheet"))
                .padding(.top, 2).padding(.bottom, 12)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(app.spots.enumerated()), id: \.element.id) { i, sp in
                    spotRow(sp, index: i, t, pal)
                    if editing == sp.id { spotEditor(sp, t, pal) }
                }
            }
        }
    }

    private func spotRow(_ sp: Spot, index i: Int, _ t: Lexicon, _ pal: Palette) -> some View {
        let name = sp.name.isEmpty ? sp.coordinate.text : sp.name
        return HStack(spacing: 10) {
            Button {
                app.movePlace(to: sp.coordinate)
                close()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 15)).foregroundStyle(pal.ink)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(height: 18)
                        .shotNode("loc.spot.\(i).name", text: name)
                    if !sp.address.isEmpty {
                        Text(sp.address).font(.system(size: 12)).foregroundStyle(pal.ink4)
                            .frame(height: 15)
                            .shotNode("loc.spot.\(i).addr", text: sp.address)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressFade())
            Button {
                editing = editing == sp.id ? nil : sp.id
                if editing != nil { focus = .spotName }
            } label: {
                PlaceGlyphView(glyph: .pencil, size: 16, line: 1.6)
                    .foregroundStyle(editing == sp.id ? pal.brass : pal.ink6)
                    .frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.t("loc.editAria"))
            .shotNode("loc.spot.\(i).edit")
            Button {
                if editing == sp.id { editing = nil }
                app.removeSpot(id: sp.id)
            } label: {
                PlaceGlyphView(glyph: .cross, size: 15, line: 1.9).foregroundStyle(pal.ink6)
                    .frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t.t("loc.delAria"))
            .shotNode("loc.spot.\(i).del")
        }
        .padding(.vertical, 10).padding(.horizontal, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair).frame(height: 1) }
        .padding(.bottom, 1)
        .shotNode("loc.spot.\(i)")
    }

    /// Правка в строке (`.spot-editbox`): два поля 14 на `--fill-b`, пишутся
    /// по мере набора — отдельное «Готово» двум полям не по чину.
    private func spotEditor(_ sp: Spot, _ t: Lexicon, _ pal: Palette) -> some View {
        VStack(spacing: 0) {
            editField(t.t("loc.namePh"), text: Binding(get: { app.spots.first { $0.id == sp.id }?.name ?? "" },
                                                        set: { app.editSpot(id: sp.id, name: $0) }),
                      field: .spotName, pal)
            editField(t.t("loc.addrPh"), text: Binding(get: { app.spots.first { $0.id == sp.id }?.address ?? "" },
                                                        set: { app.editSpot(id: sp.id, address: $0) }),
                      field: .spotAddress, pal)
        }
        .padding(.top, 4).padding(.horizontal, 2).padding(.bottom, 12)
    }

    private func editField(_ ph: String, text: Binding<String>, field: Field, _ pal: Palette) -> some View {
        TextField("", text: text, prompt: Text(ph).foregroundStyle(pal.ink6))
            .font(.system(size: 14)).foregroundStyle(pal.ink)
            .textFieldStyle(.plain)
            .focused($focus, equals: field)
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pal.fillB))
            .padding(.top, 6)
    }

    // MARK: - Путь «Геопозиция»

    private func geoWay(_ t: Lexicon, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { Task { await locate() } } label: {
                HStack(spacing: 9) {
                    PlaceGlyphView(glyph: .detect, size: 18, line: 1.8)
                    Text(t.t(detecting ? "loc.detecting" : "loc.here")).font(webFont(15, 600))
                }
                .foregroundStyle(pal.brass)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pal.pressWarm))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressFade())
            .disabled(detecting)
            .shotNode("loc.here")
            .padding(.top, 14)
            HStack(alignment: .top, spacing: 10) {
                coordField(t.t("loc.lat"), "56.021", text: Binding(get: { form.lat }, set: { form.typeCoords(lat: $0) }),
                           field: .lat, label: "loc.latLabel", node: "loc.lat", pal)
                coordField(t.t("loc.lon"), "37.482", text: Binding(get: { form.lon }, set: { form.typeCoords(lon: $0) }),
                           field: .lon, label: "loc.lonLabel", node: "loc.lon", pal)
            }
            .padding(.top, 12)
            // `.seg-note`: 12 `--ink-6`, строка 1,5 кегля — 18 на строку:
            // между строками 3,7 к своим 14,3 и по половине этого сверху и
            // снизу, как полуинтерлиньяж CSS (без него заметка ниже на 3,5).
            Text(t.t("loc.geoNote"))
                .font(.system(size: 12)).lineSpacing(3.7)
                .foregroundStyle(pal.ink6)
                .fixedSize(horizontal: false, vertical: true)
                .shotNode("loc.note", text: t.t("loc.geoNote"))
                .padding(.vertical, 1.85)
                .padding(.top, 10)
        }
    }

    /// Поле числа (`.loc-fields`): подпись 10/600 прописными, 6 до поля,
    /// поле 16 цифрами одной ширины, 13 / 14. У веба второе поле вылезает
    /// за поле листа на 24 (две колонки по 203 при ширине 392), здесь
    /// колонки делят ширину поровну.
    private func coordField(_ title: String, _ ph: String, text: Binding<String>, field: Field,
                            label: String, node: String, _ pal: Palette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold)).tracking(1).textCase(.uppercase)
                .foregroundStyle(pal.ink7)
                .frame(height: 12)
                .shotNode(label, text: title)
            TextField("", text: text, prompt: Text(ph).foregroundStyle(pal.ink8))
                .font(.system(size: 16)).monospacedDigit().foregroundStyle(pal.ink)
                .textFieldStyle(.plain)
                .numbersKeyboard()
                .autocorrectionDisabled()
                .focused($focus, equals: field)
                .padding(.vertical, 13).padding(.horizontal, 14)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(focus == field ? pal.press : .clear))
                .shotNode(node)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «Подставить моё место»: месту приложения это весь ответ — переезд и
    /// лист закрывается; отказ или нет сигнала — строка ошибки.
    private func locate() async {
        detecting = true
        form.errorKey = nil
        let r = await app.locateHere()
        detecting = false
        if case .fix = r { close() } else { form.errorKey = "loc.errNotFound" }
    }

    // MARK: - Имя, ошибка, «Готово»

    /// Имя и сохранение — общие для обоих путей (`#locPlaceGroup`); строки
    /// адреса на пути координат нет — ради мест без адреса путь и заведён.
    private func placeGroup(_ t: Lexicon, _ pal: Palette) -> some View {
        VStack(spacing: 0) {
            groupField(t.t("loc.namePh"), text: Binding(get: { form.name }, set: { form.typeName($0) }),
                       field: .name, node: "loc.name", pal)
            if form.way == .addr {
                groupField(t.t("loc.addrPh"), text: $form.address, field: .address, node: "loc.addr", pal)
                    .overlay(alignment: .top) { Rectangle().fill(pal.surface).frame(height: 1) }
            }
            HStack(spacing: 12) {
                Text(t.t("loc.saveSpot")).font(.system(size: 16)).foregroundStyle(pal.ink)
                Spacer(minLength: 0)
                Toggle("", isOn: $form.save).labelsHidden().tint(pal.brass)
            }
            .padding(.vertical, 14).padding(.horizontal, 15)
            .frame(minHeight: 59)
            .overlay(alignment: .top) { Rectangle().fill(pal.surface).frame(height: 1) }
            .shotNode("loc.save")
        }
        .shotNode("loc.group")
        .padding(.top, form.way == .addr ? 0 : 12)
    }

    private func groupField(_ ph: String, text: Binding<String>, field: Field, node: String, _ pal: Palette) -> some View {
        TextField("", text: text, prompt: Text(ph).foregroundStyle(pal.ink8))
            .font(.system(size: 16)).foregroundStyle(pal.ink)
            .textFieldStyle(.plain)
            .focused($focus, equals: field)
            .padding(15)
            .frame(height: 48)
            .shotNode(node)
    }

    /// `#locErr`: 12 `--terra`, высота не меньше 16, 8 над.
    private func errorLine(_ t: Lexicon, _ pal: Palette) -> some View {
        Text(form.errorKey.map { t.t($0) } ?? "")
            .font(.system(size: 12)).foregroundStyle(pal.terra)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 16, alignment: .topLeading)
            .padding(.top, 8)
    }

    /// «Готово»: точка из полей или строка ошибки; тумблер сохраняет место.
    private func doneButton(_ t: Lexicon, _ pal: Palette) -> some View {
        Button {
            switch form.answer() {
            case .failure(let e):
                form.errorKey = e.key
            case .success(let c):
                if form.save {
                    app.saveSpot(at: c, name: form.name, address: form.way == .addr ? form.address : "",
                                 fromHit: form.fromHit)
                }
                app.movePlace(to: c)
                close()
            }
        } label: {
            Text(t.t("pick.done"))
                .font(webFont(16, 650)).foregroundStyle(pal.onBrass)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(pal.brass))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFade())
        .shotNode("loc.done")
        .padding(.top, 20)
    }
}

/// `:active { opacity: 0.6 }` веба.
private struct PressFade: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension View {
    /// Цифровая клавиатура с точкой и минусом — у Mac её нет.
    func numbersKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numbersAndPunctuation)
        #else
        self
        #endif
    }
}
