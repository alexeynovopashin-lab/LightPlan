import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Какое колесо раскрыто под точкой дня (веб `fStopTime`, `fStopEnd`, `fHall`):
/// под списком всегда одно колесо, чей бы вопрос оно ни задавало.
enum StopWheel: Hashable {
    case start(Int), end(Int), hall(Int)
    var stop: Int { switch self { case .start(let i), .end(let i), .hall(let i): i } }
}

/// Группа «Место и адрес» / «Маршрут дня» (веб `#fPlaceGroup`, `renderRouteEditor`,
/// `renderRouteHead`): город, точки дня на нити, три пути к месту, «＋ Точка»,
/// «Повторять место и маршрут». Место съёмки — первая точка. Числа — CSS `.rt-*`.
struct FormPlaceBlock: View {
    @Bindable var app: AppModel
    let form: EventForm
    @Binding var wheel: StopWheel?
    /// Раскрыто колесо времени формы — его закрывает колесо точки, и наоборот.
    let closeOthers: () -> Void
    /// Для какой точки открыт ряд путей (веб `waysStop`).
    @State private var waysStop: Int?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let f = form
        let n = f.route.count
        let meet = f.mode == .meet
        let head = f.route.first
        let headEmpty = head.map { $0.spotId == nil && $0.studioId == nil && $0.placeText.trimmingCharacters(in: .whitespaces).isEmpty } ?? true
        let forStop = waysStop.map { f.route.indices.contains($0) } ?? false
        let waysShown = !meet && (headEmpty || forStop)
        // Ряд встаёт под той точкой, которую спрашивает; пустой список — под городом.
        let askIdx: Int? = forStop ? waysStop : (headEmpty && n > 0 ? 0 : nil)
        VStack(alignment: .leading, spacing: 0) {
            FormGroupLabel(text: t.t(n > 1 ? "card.route" : "form.placeAddr"))
                .shotNode("form.placeLabel", text: t.t(n > 1 ? "card.route" : "form.placeAddr"))
            FormGroup(node: "form.place") {
                FormTextField(placeholder: t.t("form.city"),
                              text: Binding(get: { app.form?.sessionPlace.town ?? "" }, set: { app.setFormCity($0) }))
                    .shotNode("form.city")
                if !meet && n > 0 {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<n, id: \.self) { i in
                            row(i, f, last: i == n - 1 && askIdx != i, pal, t)
                            if wheel?.stop == i { wheelView(i, f, pal) }
                            if waysShown, askIdx == i { ways(i, inList: true, pal, t) }
                        }
                        if !forStop { addButton(f, pal, t) }
                    }
                    .padding(.top, 11)
                    .shotNode("form.route")
                }
                if waysShown && askIdx == nil { ways(0, inList: false, pal, t) }
                if f.repeatOn {
                    FormToggleRow(node: "form.rep.route", label: t.t("rep.route"), on: f.repeatBlocks.contains(.route)) {
                        app.setFormRepeat(block: .route, on: $0)
                    }
                }
            }
        }
    }

    // MARK: - Точка

    private func row(_ i: Int, _ f: EventForm, last: Bool, _ pal: Palette, _ t: Lexicon) -> some View {
        let r = f.route[i]
        let hint = t.t("scene." + SceneHints.key(f.genre, i))
        let lit = wheel?.stop == i
        return HStack(alignment: .top, spacing: 11) {
            // Узел на нити: номер в кружке, линия под ним тянется к следующему.
            VStack(spacing: 5) {
                Text("\(i + 1)").font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(lit ? pal.brass : pal.ink3)
                    .frame(width: 24, height: 24)
                    .background(lit ? Color(hex: 0xE2A44C, alpha: 0.16) : pal.field, in: Circle())
                    .overlay(Circle().strokeBorder(lit ? pal.pressBrass : pal.rail, lineWidth: 1))
                if !last && !lit { Rectangle().fill(pal.rail).frame(width: 1).frame(maxHeight: .infinity) }
            }
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    TextField("", text: Binding(get: { app.form?.route[safe: i]?.name ?? "" }, set: { app.setFormStopName(i, $0) }),
                              prompt: Text(hint).font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.ink8))
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(pal.ink)
                        .textFieldStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { if wheel != nil { wheel = nil } })
                        .shotNode("form.stop.\(i).name")
                    span(i, r, pal)
                    Button { remove(i) } label: {
                        Text("✕").font(.system(size: 14)).foregroundStyle(pal.ink9)
                            .padding(.vertical, 6).padding(.leading, 2).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.t("gen.removeAria"))
                    .shotNode("form.stop.\(i).x")
                }
                placeLine(i, r, pal, t).padding(.top, 5)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 14)
        .fixedSize(horizontal: false, vertical: true)
        .shotNode("form.stop.\(i)")
    }

    /// Промежуток одной пилюлей: половины нажимаются по отдельности (`.rt-span`).
    private func span(_ i: Int, _ r: RoutePoint, _ pal: Palette) -> some View {
        HStack(spacing: 3) {
            half(r.start, open: wheel == .start(i), pal) { open(.start(i)) }
                .shotNode("form.stop.\(i).t1")
            Text("–").font(.system(size: 13)).foregroundStyle(pal.ink7)
            half(r.end, open: wheel == .end(i), pal) { open(.end(i)) }
                .shotNode("form.stop.\(i).t2")
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(pal.field, in: Capsule())
        .fixedSize()
    }

    private func half(_ m: Int?, open: Bool, _ pal: Palette, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(m.map { clock.fmt(Double($0)) } ?? "—:—")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(open ? pal.brass : (m == nil ? pal.ink8 : pal.ink))
        }
        .buttonStyle(.plain)
    }

    /// Вторая строка: булавка — кнопка выбора места; у студии — капсула залов.
    private func placeLine(_ i: Int, _ r: RoutePoint, _ pal: Palette, _ t: Lexicon) -> some View {
        let linked = r.spotId != nil || r.studioId != nil
        return HStack(spacing: 6) {
            Button { pin(i, linked: linked) } label: {
                Icon("pin", size: 13, line: 1.8)
                    .foregroundStyle(linked ? pal.brass : pal.ink7)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -5)
            .accessibilityLabel(t.t("form.pickSpotAria"))
            .shotNode("form.stop.\(i).pin")
            if r.studioId != nil {
                let open = wheel == .hall(i)
                Button { self.open(.hall(i)) } label: {
                    Text(r.placeText).font(.system(size: 13)).lineLimit(1)
                        .foregroundStyle(open ? pal.brass : pal.ink4)
                        .padding(.vertical, open ? 7 : 0).padding(.horizontal, open ? 11 : 0)
                        .background(open ? Color(hex: 0xE2A44C, alpha: 0.16) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .padding(.vertical, open ? -7 : 0).padding(.horizontal, open ? -11 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.t("form.pickHallAria"))
                .shotNode("form.stop.\(i).hall")
            } else {
                TextField("", text: Binding(get: { app.form?.route[safe: i]?.placeText ?? "" }, set: {
                    app.setFormStopPlaceText(i, $0)
                    if waysStop == i { waysStop = nil }
                }), prompt: Text(t.t("form.scenePlacePh")).foregroundStyle(pal.ink9))
                    .font(.system(size: 13)).foregroundStyle(pal.ink4)
                    .textFieldStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { if wheel != nil { wheel = nil } })
                    .shotNode("form.stop.\(i).place")
            }
        }
    }

    // MARK: - Колёса

    @ViewBuilder
    private func wheelView(_ i: Int, _ f: EventForm, _ pal: Palette) -> some View {
        switch wheel {
        case .start(let j), .end(let j):
            let end = wheel == .end(j)
            let r = f.route[j]
            let cur = (end ? r.end : r.start) ?? f.stopTimeSeed(j, end: end, step: app.settings.timeStep)
            FormTimeWheel(minute: cur, step: app.settings.timeStep, twelveHour: clock.is12, language: app.language) { m in
                app.setFormStopTime(j, end: end, minute: Self.fit(m, near: cur, in: f))
            }
            .padding(.leading, 35).padding(.trailing, 10)
            .shotNode("form.stopWheel")
        case .hall(let j):
            if let st = app.studios.first(where: { $0.id == f.route[j].studioId }) {
                let cells: [Studio.Hall?] = [nil] + st.halls
                Picker("", selection: Binding(get: { f.route[j].hallId ?? "" }, set: { id in
                    app.setFormStopHall(j, hall: st.halls.first { $0.id == id })
                })) {
                    ForEach(cells.indices, id: \.self) { k in
                        Text(cells[k]?.name ?? st.name).tag(cells[k]?.id ?? "")
                    }
                }
                #if os(iOS)
                .pickerStyle(.wheel)
                #endif
                .frame(height: 140)
                .padding(.leading, 35).padding(.trailing, 10)
                .shotNode("form.hallWheel")
            }
        case nil:
            EmptyView()
        }
    }

    /// Минута дня с колеса → минута съёмки: день берётся тот, где колесо ближе к
    /// прежнему значению, и час держится в часах самой съёмки (веб `fillStopHours`:
    /// остальные часы приглушены и не выбираются — отпущенное колесо доезжает до
    /// ближайшего допустимого).
    static func fit(_ wheelMinute: Int, near cur: Int, in f: EventForm) -> Int {
        let day0 = Int((Double(cur) / 1440).rounded(.down))
        let cands = [day0 - 1, day0, day0 + 1].map { $0 * 1440 + wheelMinute }
        let m = cands.min { abs($0 - cur) < abs($1 - cur) } ?? wheelMinute
        let h = f.stopHours
        return min(max(m, h.lo * 60), h.hi * 60 + 59)
    }

    // MARK: - Три пути, «＋»

    /// `.place-ways`: три равные кнопки, знак над словом, подложка `--press`.
    private func ways(_ i: Int, inList: Bool, _ pal: Palette, _ t: Lexicon) -> some View {
        HStack(spacing: 8) {
            way(.addr, icon: "city", "loc.wayAddr", i, pal, t)
            way(.studio, icon: "studio", "loc.wayStudio", i, pal, t)
            way(.geo, icon: "route", "loc.wayGeo", i, pal, t)
        }
        .padding(.vertical, 12).padding(.leading, inList ? 35 : 15).padding(.trailing, 15)
        .overlay(alignment: .top) { if inList { Rectangle().fill(pal.surface).frame(height: 1) } }
        .padding(.bottom, inList ? 12 : 0)
        .shotNode("form.ways")
    }

    private func way(_ w: PlaceSheetForm.Way, icon: String, _ key: String, _ i: Int, _ pal: Palette, _ t: Lexicon) -> some View {
        Button {
            wheel = nil
            // Пустой список: первая точка заводится этим же нажатием.
            if app.form?.route.isEmpty == true { app.addFormStop() }
            app.openStopPlace(i, way: w)
        } label: {
            VStack(spacing: 5) {
                Icon(icon, size: 17, line: 1.6)
                Text(t.t(key)).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(pal.ink3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10).padding(.horizontal, 4)
            .background(pal.press, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("form.way.\(w.rawValue)")
    }

    /// «Точка» — последний узел нити: пустой кружок с плюсом (`.rt-add`).
    private func addButton(_ f: EventForm, _ pal: Palette, _ t: Lexicon) -> some View {
        Button {
            wheel = nil
            guard app.form.map({ $0.route.count < EventForm.maxStops }) == true else { return }
            app.addFormStop()
            waysStop = (app.form?.route.count ?? 1) - 1
        } label: {
            HStack(spacing: 11) {
                Icon("plus", size: 12, line: 2).foregroundStyle(pal.ink5)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(pal.rail, lineWidth: 1))
                Text(t.t("form.addStopShort")).font(.system(size: 14.5)).foregroundStyle(pal.ink4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shotNode("form.addStop")
    }

    // MARK: - Действия

    /// Тап по половине пилюли: второй тап сворачивает; пустая клетка сразу
    /// получает подсказанный час — колесо встало на него, это уже ответ.
    private func open(_ w: StopWheel) {
        closeOthers()
        if wheel == w { withAnimation(.easeOut(duration: 0.34)) { wheel = nil }; return }
        withAnimation(.easeOut(duration: 0.34)) { wheel = w }
        guard let f = app.form else { return }
        switch w {
        case .start(let i) where f.route[safe: i]?.start == nil:
            app.setFormStopTime(i, end: false, minute: f.stopTimeSeed(i, end: false, step: app.settings.timeStep))
        case .end(let i) where f.route[safe: i]?.end == nil:
            app.setFormStopTime(i, end: true, minute: f.stopTimeSeed(i, end: true, step: app.settings.timeStep))
        default: break
        }
    }

    /// Булавка: есть ссылка — выбор из своих мест (путь «Место»); нет — ряд путей,
    /// второй тап его закрывает.
    private func pin(_ i: Int, linked: Bool) {
        wheel = nil
        if linked {
            app.openStopPlace(i, way: .addr)
        } else {
            withAnimation(.easeOut(duration: 0.2)) { waysStop = waysStop == i ? nil : i }
        }
    }

    private func remove(_ i: Int) {
        wheel = nil
        waysStop = nil
        app.removeFormStop(i)
    }

    private var clock: ClockText {
        ClockText(language: app.language, preference: ClockPreference(rawValue: app.settings.clock.rawValue) ?? .auto)
    }
}

/// Группа «Нужна погода» (веб `#fWishGroup`, `renderWishes`): восемь плиток `.tool`,
/// «Неважно» — пустой список. Встрече не показывается.
struct FormWishBlock: View {
    @Bindable var app: AppModel
    let form: EventForm
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let all = Wish.allCases
        let rows = stride(from: 0, to: all.count, by: GenreGrid.columns).map { Array(all[$0..<min($0 + GenreGrid.columns, all.count)]) }
        VStack(alignment: .leading, spacing: 0) {
            FormGroupLabel(text: t.t("form.wish"))
            FormGroup(node: "form.wish") {
                VStack(spacing: 6) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 6) {
                            ForEach(rows[r], id: \.self) { w in tile(w, pal, t) }
                        }
                    }
                }
                .padding(.top, 13).padding(.horizontal, 15).padding(.bottom, 15)
                if form.repeatOn {
                    FormToggleRow(node: "form.rep.wish", label: t.t("rep.wish"), on: form.repeatBlocks.contains(.wish)) {
                        app.setFormRepeat(block: .wish, on: $0)
                    }
                }
            }
        }
    }

    private func tile(_ w: Wish, _ pal: Palette, _ t: Lexicon) -> some View {
        let on = form.wishOn(w)
        let name = t.t("wish." + w.rawValue)
        return Button { app.toggleFormWish(w) } label: {
            VStack(spacing: 6) {
                Icon(wish: w.rawValue, size: 22, line: 1.5)
                Text(name).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? pal.brass : pal.ink5)
            .frame(maxWidth: .infinity)
            .padding(.top, 11).padding(.horizontal, 2).padding(.bottom, 9)
            .background(on ? pal.pressWarm : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
        .shotNode("form.wish.\(w.rawValue)")
    }
}

/// «Замысел против прогноза» вверху формы (`.wish-warn`): плашка `--sheet` со
/// спокойным янтарным светом из-под неё, знак 16 `--brass-deep` слева.
struct FormWishWarn: View {
    let warning: WishWarning
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme)
        VStack(alignment: .leading, spacing: 2) {
            Text(warning.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(pal.ink)
            Text(warning.message).font(.system(size: 13)).foregroundStyle(pal.ink4)
        }
        .lineSpacing(13 * 0.5 - 3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12).padding(.trailing, 14).padding(.leading, 40)
        .overlay(alignment: .topLeading) {
            Icon("warn", size: 16, line: 1.5).foregroundStyle(pal.brassDeep).padding(.leading, 14).padding(.top, 13)
        }
        .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .modifier(WarnGlow(rgb: (226, 164, 76), alpha: scheme == .light ? 0.55 : 0.32))
        .padding(.top, 10)
        .shotNode("form.wishWarn", text: warning.title)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
