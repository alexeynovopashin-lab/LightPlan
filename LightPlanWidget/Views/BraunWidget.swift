import SwiftUI
import LightPlanDomain
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// 30б.2в-4 — средний и малый виджет, пока съёмка идёт: перенос демки Алексея 26.10 один в один
// (`light_plan:Light_Plan/docs/widget_design_2026-10-26/`: `Spec.dc.html` — числа, `Widget.dc.html` — формулы `renderVals()`, `ticks()`, `fit()`).
// Числа и правила (круг, барабан, риски, подбор шрифта) — в Domain (`WidgetBraun.swift`, под `swift test`); здесь палитра, замер текста,
// раскладка и сами виды. Всё стоит на заданных pt, как в демке: плашку виду сообщает `GeometryReader`, шрифты не растут от Dynamic Type.

// MARK: - Палитра «Braun»

/// Цвета часов Braun (слова Алексея 26.10: «это цвета часов браун, хочу потестировать эту палитру»): светлая — «Braun белый» (`light` демки),
/// тёмная — «Braun чёрный» (`braunDark`). Тёплая `dark` демки (#1f1e1b) не используется. Следует за системной светлой/тёмной темой.
struct BraunPalette {
    let dark: Bool

    private static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
    }
    private func pick(_ light: UInt32, _ dark: UInt32) -> Color { Self.hex(self.dark ? dark : light) }

    var bg: Color { pick(0xE4E4E2, 0x161616) }
    var text: Color { pick(0x111111, 0xECECEA) }
    var muted: Color { pick(0x5B5B5B, 0x9B9B9B) }
    /// Тусклый — соседи барабана через одну.
    var dim: Color { pick(0x7A7A7A, 0x6B6B6B) }
    /// Текущая точка: текст и знак. В светлой — чёрный (на жёлтой подложке), в тёмной — жёлтый стрелки Braun.
    var amber: Color { pick(0x111111, 0xF4B400) }
    var dot: Color { pick(0x111111, 0xECECEA) }
    var dotOff: Color { pick(0xDCDCDA, 0x2E2E2E) }
    var tickOff: Color { pick(0xCBCBC9, 0x303030) }
    var tickMinor: Color { pick(0x6E6E6E, 0x8C8C8C) }
    var tickHour: Color { pick(0x111111, 0xECECEA) }
    var dial: Color { pick(0xFAFAFA, 0x0D0D0D) }
    var dialEdge: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }
    /// Подложка центра барабана: в светлой жёлтая, в тёмной белый 7 %.
    var pill: Color { dark ? Color.white.opacity(0.07) : Self.hex(0xF4B400) }
    /// Окошко свадьбы.
    var win: Color { pick(0xD3D3D1, 0x0A0A0A) }
    var winTopShadow: Color { Color.black.opacity(dark ? 0.7 : 0.25) }
    var winBottomRim: Color { Color.white.opacity(dark ? 0.08 : 0.8) }
    /// Обводка окошка только в тёмной.
    var winRing: Color? { dark ? Color.white.opacity(0.12) : nil }
    /// Красный флажок Braun над окошком.
    var flag: Color { pick(0xAD0A15, 0xC8102E) }
}

// MARK: - Замер текста

/// Ширина строки шрифтом системы — для `fit()` (шрифт меньше, потом две строки). Тот же шрифт, что рисует `Text(.system(size:weight:))`.
enum BraunText {
    #if canImport(UIKit)
    private typealias Face = UIFont
    #else
    private typealias Face = NSFont
    #endif

    private static func face(_ size: Double, semibold: Bool, mono: Bool) -> Face {
        let w: Face.Weight = semibold ? .semibold : .medium
        return mono ? Face.monospacedDigitSystemFont(ofSize: CGFloat(size), weight: w) : Face.systemFont(ofSize: CGFloat(size), weight: w)
    }

    static func width(_ text: String, size: Double, semibold: Bool, mono: Bool = false, tracking: Double = 0) -> Double {
        let s = NSAttributedString(string: text, attributes: [.font: face(size, semibold: semibold, mono: mono), .kern: tracking])
        return Double(s.size().width)
    }

    /// Высота строки шрифта без добавок — чтобы довести её до высоты строки демки (`lineSpacing`).
    static func naturalLineHeight(size: Double, semibold: Bool) -> Double {
        #if canImport(UIKit)
        Double(face(size, semibold: semibold, mono: false).lineHeight)
        #else
        Double(face(size, semibold: semibold, mono: false).ascender - face(size, semibold: semibold, mono: false).descender)
        #endif
    }
}

// MARK: - Раскладка

/// Раскладка плашки: все координаты pt, формулы `renderVals()` демки. Не рисует, а считает — виды ставят по этим числам, тест сверяет их с демкой.
struct BraunLayout {
    struct Row {
        var slot: BraunDrum.Slot
        var stop: WidgetFeed.Stop?
        /// Состояние Б (30б.2в-5): строка барабана света вместо точки маршрута.
        var light: BraunIdle.LightItem? = nil
        var step: BraunFit.Step
        /// Оценка заката в конце строки заката («хороший»); только у сегодняшнего заката и только если прогноз есть.
        var extra: String? = nil
        /// Оценка не влезла рядом с названием центра даже без знака — она второй строкой под названием (подложка в две строки, 42 pt).
        var extraStacked = false
        /// Кегль слова оценки: 11; на самой узкой строке (338, ±1 рядом с оценкой) — 10 или 9.
        var extraSize = 11.0
        /// Знак оценки в хвосте: на узкой плашке (338) для слова не хватает места, и знак уходит первым — слово остаётся целым.
        var extraIcon = true
    }

    let size: CGSize
    let medium: Bool
    let radius: Double
    /// Имена в шапке: клиенты, а нет их в файле — название жанра.
    let names: String
    /// Ширина окошка свадьбы (поля внутри), 0 в малом.
    let windowWidth: Double
    let headerWidth: Double
    let header: BraunFit.Step
    let headerHeight: Double
    let diameter: Double
    let cx: Double, cy: Double
    /// Колонка барабана (в среднем).
    let drum: CGRect
    let centerStep: BraunFit.Step
    let rows: [Row]
    /// Поля под приставку и суффикс времени барабана света (AM / PM при 12-часовых часах), 0 — при 24-часовых.
    let timeBefore: Double, timeAfter: Double
    /// Поля строки и зазор до названия на барабане света: 10 / 8; при 12-часовых часах (AM / PM занимает место) — 6 / 5.
    let rowPadding: Double, timeGap: Double
    /// Ширина под название в строке барабана света с учётом полей, зазора и суффикса времени.
    let drumNameWidth: Double
    /// Состояние Б «Семьи виджетов» (30б.2в-5): маршрута нет — круг считает всю съёмку, справа свет, окошко с вырезом-флажком.
    let bare: Bool

    static let windowText = "00:00:00"
    /// Знак и зазор до названия в строке барабана света: центр 16 + 5, остальные 13 + 5.
    static func lightSignWidth(offset: Int) -> Double { (offset == 0 ? 16 : 13) + 5 }
    /// Хвост строки заката: зазор строки 5 + поле 3, знак 12, зазор 3, слово оценки 11 medium (как у доски: слово начинается через 8 после «Закат»).
    static func ratingWidth(_ word: String, icon: Bool = true, size: Double = 11) -> Double { 5 + 3 + (icon ? 12 + 3 : 0) + BraunText.width(word, size: size, semibold: false) }

    init(plan: DayPlan, size: CGSize, medium: Bool, bare wantsBare: Bool = false) {
        let bare = wantsBare && medium
        let w = Double(size.width), h = Double(size.height), pad = BraunPlate.pad
        let named = (plan.shoot.names ?? "").trimmingCharacters(in: .whitespaces)
        let text = named.isEmpty ? plan.shoot.title : named

        // Окошко: ширина по «00:00:00» (13 semibold, цифры одной ширины), чтобы рамка не прыгала; поля 6, +2 запаса, как `labelW` демки.
        let window = medium ? BraunText.width(Self.windowText, size: 13, semibold: true, mono: true) + 2 + 12 + (bare ? BraunWindow.notchExtra : 0) : 0
        let headW = w - 2 * pad - (medium ? window + 10 + (bare ? 0 : BraunWindow.flagReserve) : 0)
        let head = BraunFit.pick(medium ? BraunFit.headerMedium : BraunFit.headerSmall, avail: headW - BraunPlate.signAndGap) {
            BraunText.width(text, size: $0, semibold: true, tracking: -0.1)
        }
        let headH = BraunPlate.headerHeight(lines: head.lines)
        let d = BraunPlate.dialDiameter(plateHeight: h, headerHeight: headH)
        let centreY = pad + headH + 4 + d / 2

        let dx = pad + d + BraunDrum.columnGap
        let column = CGRect(x: dx, y: centreY - d / 2, width: w - pad - dx, height: d)
        let lights = bare ? BraunIdle.lightDrum(plan.frame) : []
        let timeReserve = ColonTime.reserves(lights.compactMap { $0 }.map { plan.frame.clock($0.at, in: plan.frame.zone) })
        let tight = timeReserve.before + timeReserve.after > 0
        let rowPad = tight ? 6.0 : BraunDrum.rowPadding, gap = tight ? 5.0 : BraunDrum.gap
        let nameAvail = Double(column.width) - 2 * rowPad - BraunDrum.timeColumn - gap - timeReserve.before - timeReserve.after
        let items = bare ? [] : BraunDrum.neighbours(plan.stops, current: plan.currentIndex)
        let currentName = items.isEmpty ? "" : (items[2]?.name ?? "")
        // Оценка стоит в строке того события, которое виджет оценивает сейчас (30б.2в-6): рассвет до конца золотого часа, потом закат, после — завтрашний рассвет.
        let rated = bare ? BraunIdle.ratedEvent(plan.frame) : nil
        let ratingWord = bare ? BraunIdle.ratingWord(plan.frame) : nil
        func lightName(_ it: BraunIdle.LightItem?) -> String {
            guard let it else { return "" }
            return plan.words[it.kind == .sunrise ? .sunrise : (it.kind == .golden ? .golden : .sunset)]
        }
        func lightExtra(_ it: BraunIdle.LightItem?) -> String? { it != nil && it?.kind == rated?.kind && it?.tomorrow == rated?.tomorrow ? ratingWord : nil }
        func lightAvail(_ offset: Int, icon: Bool = true, word: Double = 11) -> Double {
            nameAvail - Self.lightSignWidth(offset: offset) - (lightExtra(lights[offset + 2]).map { Self.ratingWidth($0, icon: icon, size: word) } ?? 0)
        }
        // Центр барабана света с оценкой: оценка рядом с названием, если влезает (со знаком, потом без), иначе второй строкой под ним.
        var centreStacked = false, centreIcon = true
        let centre: BraunFit.Step
        if bare {
            let name0 = lightName(lights[2])
            func single(_ avail: Double) -> BraunFit.Step? {
                BraunFit.centerRow.first { $0.lines == 1 && BraunText.width(name0, size: $0.size, semibold: true) <= avail }
            }
            if lightExtra(lights[2]) == nil {
                centre = BraunFit.pick(BraunFit.centerRow, avail: lightAvail(0)) { BraunText.width(name0, size: $0, semibold: true) }
            } else if let s = single(lightAvail(0, icon: true)) {
                centre = s
            } else if let s = single(lightAvail(0, icon: false)) {
                centre = s
                centreIcon = false
            } else {
                centreStacked = true
                centre = single(nameAvail - Self.lightSignWidth(offset: 0)) ?? BraunFit.centerRow[1]
            }
        } else {
            centre = BraunFit.pick(BraunFit.centerRow, avail: nameAvail) { BraunText.width(currentName, size: $0, semibold: true) }
        }
        let slots = bare ? BraunIdle.drumSlots(diameter: d, centerLines: centreStacked ? 2 : centre.lines) : BraunDrum.slots(diameter: d, centerLines: centre.lines)

        self.size = size
        self.medium = medium
        radius = BraunPlate.cornerRadius(plateHeight: h)
        names = text
        windowWidth = window
        headerWidth = headW
        header = head
        headerHeight = headH
        diameter = d
        cx = medium ? pad + d / 2 : w / 2
        cy = centreY
        drum = column
        centerStep = centre
        self.bare = bare
        timeBefore = timeReserve.before
        timeAfter = timeReserve.after
        rowPadding = bare ? rowPad : BraunDrum.rowPadding
        timeGap = bare ? gap : BraunDrum.gap
        drumNameWidth = nameAvail
        rows = bare ? slots.map { slot in
            let light = lights[slot.offset + 2]
            let name = lightName(light)
            func pick(_ icon: Bool, _ word: Double) -> BraunFit.Step {
                slot.offset == 0 ? centre : BraunFit.pick(BraunFit.nearRow + (word < 11 ? [BraunFit.Step(10, lineHeight: 18), BraunFit.Step(9, lineHeight: 18)] : []), avail: lightAvail(slot.offset, icon: icon, word: word)) { BraunText.width(name, size: $0, semibold: false) }
            }
            // Название мельчает до 11; не влезло и так — из хвоста уходит знак оценки, потом слово мельчает до 10, а при нужде до 9, и название до 10 или 9: оба остаются целыми.
            var icon = slot.offset == 0 ? centreIcon : true
            var wordSize = 11.0
            var step = pick(icon, wordSize)
            if lightExtra(light) != nil, slot.offset != 0 {
                func fits() -> Bool { BraunText.width(name, size: step.size, semibold: false) <= lightAvail(slot.offset, icon: icon, word: wordSize) }
                if !fits() { icon = false; step = pick(icon, wordSize) }
                if !fits() { wordSize = 10; step = pick(icon, wordSize) }
                if !fits() { wordSize = 9; step = pick(icon, wordSize) }
            }
            return Row(slot: slot, stop: nil, light: light, step: step, extra: lightExtra(light), extraStacked: slot.offset == 0 && centreStacked, extraSize: wordSize, extraIcon: icon)
        } : medium ? slots.map { slot in
            let stop = items[slot.offset + 2]
            let name = stop?.name ?? ""
            let step: BraunFit.Step
            switch abs(slot.offset) {
            case 0: step = centre
            case 1: step = BraunFit.pick(BraunFit.nearRow, avail: nameAvail) { BraunText.width(name, size: $0, semibold: false) }
            default: step = BraunFit.pick(BraunFit.farRow, avail: nameAvail) { BraunText.width(name, size: $0, semibold: false) }
            }
            return Row(slot: slot, stop: stop, step: step)
        } : []
    }
}

// MARK: - Живой таймер окошка

private struct FrozenTimerKey: EnvironmentKey { static let defaultValue = false }

private struct FlatGlassKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Линза столбика оценки на телефоне — системное стекло; `ImageRenderer` (тесты, снимки) его не рисует, там вид берёт плоскую плашку.
    var widgetFlatGlass: Bool {
        get { self[FlatGlassKey.self] }
        set { self[FlatGlassKey.self] = newValue }
    }

    /// Окошко свадьбы рисует `Text(timerInterval:)`, а он идёт по часам телефона, не по часам кадра. Для снимков и тестов, где кадр стоит на
    /// заданном моменте, вид рисует вместо него ту же строку статично.
    var widgetFrozenTimer: Bool {
        get { self[FrozenTimerKey.self] }
        set { self[FrozenTimerKey.self] = newValue }
    }
}

// MARK: - Вид

/// Средний и малый вид, пока съёмка идёт (`WidgetRoot`): риски по периметру, шапка, часы точки, у среднего ещё окошко свадьбы и барабан маршрута.
struct BraunWidgetView: View {
    let frame: WidgetFrame
    var alpha = false
    let medium: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { g in
            if let plan = DayPlan(frame), g.size.width > 0, g.size.height > 0 {
                BraunContent(plan: plan, layout: BraunLayout(plan: plan, size: g.size, medium: medium, bare: BraunIdle.isBare(frame)), alpha: alpha,
                             pal: BraunPalette(dark: scheme == .dark))
            }
        }
    }
}

struct BraunContent: View {
    let plan: DayPlan
    let layout: BraunLayout
    let alpha: Bool
    let pal: BraunPalette
    @Environment(\.widgetFrozenTimer) private var frozen

    var body: some View {
        let L = layout
        let w = Double(L.size.width), pad = BraunPlate.pad
        ZStack(alignment: .topLeading) {
            // Фон рисует сам вид: подложку плашки (`containerBackground`) система на «Домой» осветляет — 26.10 на телефоне #161616 вышел
            // #2e2e2e (а прежний #0f0e0c — #2e2d2a), и пройденные риски #303030 на ней пропадали. Цвета внутри вида доходят точно.
            Rectangle().fill(pal.bg).frame(width: L.size.width, height: L.size.height)
            ticks
            header.frame(width: L.headerWidth, height: L.headerHeight, alignment: .leading).offset(x: pad, y: pad)
            dial.offset(x: L.cx - L.diameter / 2, y: L.cy - L.diameter / 2)
            if L.bare {
                // Б: в центре знак жанра и сколько осталось всей съёмки.
                WidgetIcon(name: plan.shoot.genre, size: 20, line: 1.5, genre: true).foregroundStyle(pal.amber)
                    .frame(width: 20, height: 20).offset(x: L.cx - 10, y: L.cy - 25)
                countdown.offset(x: L.cx - BraunDial.dotRadius(diameter: L.diameter), y: L.cy - 1)
            } else if plan.current != nil {
                WidgetIcon(name: plan.current?.sign, size: 20, line: 1.5).foregroundStyle(pal.amber)
                    .frame(width: 20, height: 20).offset(x: L.cx - 10, y: L.cy - 25)
                countdown.offset(x: L.cx - BraunDial.dotRadius(diameter: L.diameter), y: L.cy - 1)
            }
            if L.bare {
                BraunLightDrum(layout: L, plan: plan, pal: pal).offset(x: L.drum.minX, y: L.drum.minY)
            } else if L.medium {
                drum.frame(width: L.drum.width, height: L.drum.height, alignment: .topLeading).clipped().offset(x: L.drum.minX, y: L.drum.minY)
            }
            // Окошко свадьбы — слоями-соседями, живой таймер последним: на телефоне 26.10 после окошка не рисовалось ничего (диагностика).
            if L.bare {
                // Флажок «Семьи виджетов» — сам левый край окошка (Алексей 27.10).
                BraunNotchWindow(pal: pal).frame(width: L.windowWidth, height: 18).offset(x: w - pad - L.windowWidth, y: pad)
            } else if L.medium {
                windowPlate(L.windowWidth).offset(x: w - pad - L.windowWidth, y: pad)
                let windowX = w - pad - L.windowWidth
                BraunFlag().fill(pal.flag).frame(width: BraunWindow.flagWidth, height: BraunWindow.flagHeight)
                    .offset(x: BraunWindow.flagX(windowX: windowX), y: BraunWindow.flagY(windowY: pad))
            }
            if alpha {
                // 6 от края: при отступе 1 скругление плашки (22) срезало значок на телефоне 26.10.
                AlphaBadge().frame(width: L.size.width - 12, height: L.size.height - 12, alignment: .bottomTrailing)
            }
            if L.medium {
                // С вырезом (Б) текст стоит после полосы флажка: рамка таймера уже на 9 слева.
                let inset = L.bare ? BraunWindow.notchExtra : 0
                timerText(max(0, plan.shoot.endDate.timeIntervalSince(plan.frame.now)))
                    .frame(width: L.windowWidth - inset, height: 18).offset(x: w - pad - L.windowWidth + inset, y: pad)
            }
        }
        .frame(width: L.size.width, height: L.size.height, alignment: .topLeading)
    }

    // MARK: Риски по периметру — вся съёмка

    private var ticks: some View {
        let shoot = plan.shoot
        let duration = shoot.endDate.timeIntervalSince(shoot.startDate)
        let elapsed = plan.frame.now.timeIntervalSince(shoot.startDate)
        let startLocal = shoot.startDate.timeIntervalSince1970 + Double(plan.zone.secondsFromGMT(for: shoot.startDate))
        let hours = BraunTicks.hourIndexes(start: startLocal, duration: duration)
        func layer(_ past: Bool, _ hour: Bool) -> some View {
            BraunTickLayer(radius: layout.radius, past: past, hour: hour, duration: duration, elapsed: elapsed, hours: hours)
                .stroke(past ? pal.tickOff : (hour ? pal.tickHour : pal.tickMinor),
                        style: StrokeStyle(lineWidth: hour ? BraunTicks.hourWidth : BraunTicks.minorWidth, lineCap: .round))
        }
        return ZStack {
            layer(true, false); layer(true, true); layer(false, false); layer(false, true)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(false)
    }

    // MARK: Шапка: знак жанра и имена

    private var header: some View {
        let step = layout.header
        let natural = BraunText.naturalLineHeight(size: step.size, semibold: true)
        return HStack(spacing: 6) {
            WidgetIcon(name: plan.shoot.genre, size: 16, line: 1.5, genre: true).foregroundStyle(pal.text)
            Text(layout.names)
                .font(.system(size: step.size, weight: .semibold)).tracking(-0.1)
                .lineSpacing(max(0, step.lineHeight - natural))
                .lineLimit(step.lines).multilineTextAlignment(.leading)
                .foregroundStyle(pal.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Окошко Braun: сколько осталось свадьбы

    private func windowPlate(_ width: Double) -> some View {
        let r = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return ZStack {
            // Утоплено: тень у верхней кромки и светлая кромка снизу — обычными заливками (`.shadow(.inner)` виджет не рисует).
            r.fill(pal.win)
            r.fill(LinearGradient(colors: [pal.winTopShadow, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.22)))
            r.fill(LinearGradient(colors: [.clear, pal.winBottomRim], startPoint: UnitPoint(x: 0.5, y: 0.9), endPoint: .bottom))
            if let ring = pal.winRing { r.strokeBorder(ring, lineWidth: 0.5) }
        }
        .frame(width: width, height: 18)
    }

    /// От часа «10:42:00», меньше часа «42:00»; тикает сама (`Text(timerInterval:)`), без обновления виджета.
    @ViewBuilder private func timerText(_ remaining: TimeInterval) -> some View {
        let font = Font.system(size: 13, weight: .semibold).monospacedDigit()
        if frozen {
            Text(BraunWindow.text(remaining: remaining)).font(font).foregroundStyle(pal.text).lineLimit(1).fixedSize()
        } else {
            let now = plan.frame.now
            // Как таймер студии, что на телефоне рисуется (`WidgetStyle`): без `.fixedSize()` и `lineLimit` — с ними 26.10 на телефоне
            // таймер не рисовался и обрывал всё, что виджет строил после него (значок «α», подложку). Ширину задаёт рамка окошка снаружи.
            Text(timerInterval: now...max(plan.shoot.endDate, now.addingTimeInterval(1)), countsDown: true, showsHours: BraunWindow.showsHours(remaining: remaining))
                .font(font).foregroundStyle(pal.text).multilineTextAlignment(.center)
        }
    }

    // MARK: Часы точки

    private var dial: some View {
        let d = layout.diameter
        // Б: горят `round(60 × осталось / вся съёмка)` точек; иначе — минуты точки, как в А.
        let minutes = layout.bare
            ? BraunIdle.wholeShootLit(left: plan.shootLeft, total: plan.shoot.endDate.timeIntervalSince(plan.shoot.startDate))
            : Int(((plan.pointLeft ?? 0) / 60).rounded(.up))
        return ZStack {
            Circle().fill(pal.dial)
            Circle().strokeBorder(pal.dialEdge, lineWidth: 0.5)
            BraunDotLayer(diameter: d, minutes: minutes, lit: false).fill(pal.dotOff)
            BraunDotLayer(diameter: d, minutes: minutes, lit: true).fill(pal.dot)
        }
        .frame(width: d, height: d)
    }

    /// «12 мин» / «1 ч 42 мин»; ноль приглушён.
    private var countdown: some View {
        let d = layout.diameter
        let minutes = Int(((layout.bare ? plan.shootLeft : (plan.pointLeft ?? 0)) / 60).rounded(.up))
        let parts = BraunDial.countdown(minutes: minutes)
        let sizes = layout.bare ? BraunIdle.countdownSizes(diameter: d, parts: parts) : (BraunDial.numberSize(diameter: d), BraunDial.unitSize(diameter: d))
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            ForEach(parts.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(parts[i].value)").font(.system(size: sizes.0, weight: .semibold)).monospacedDigit().tracking(-0.3)
                        .foregroundStyle(minutes == 0 ? pal.muted : pal.text)
                    Text(plan.words[parts[i].unit == .hour ? .hourShort : .minShort])
                        .font(.system(size: sizes.1, weight: .medium)).foregroundStyle(pal.muted)
                }
            }
        }
        .lineLimit(1)
        .frame(width: 2 * BraunDial.dotRadius(diameter: d), height: 26)
    }

    // MARK: Барабан маршрута

    private var drum: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.rows.indices, id: \.self) { i in
                let row = layout.rows[i]
                if let stop = row.stop { drumRow(row, stop).offset(y: row.slot.y) }
            }
        }
    }

    private func drumRow(_ row: BraunLayout.Row, _ stop: WidgetFeed.Stop) -> some View {
        let o = abs(row.slot.offset)
        let timeSize: Double = o == 0 ? 16 : (o == 1 ? 13 : 11)
        let weight: Font.Weight = o == 0 ? .semibold : .medium
        let color = o == 0 ? pal.amber : (o == 1 ? pal.muted : pal.dim)
        let natural = BraunText.naturalLineHeight(size: row.step.size, semibold: o == 0)
        return HStack(spacing: BraunDrum.gap) {
            Text(plan.frame.clock(stop.date, in: plan.zone))
                .font(.system(size: timeSize, weight: weight)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: BraunDrum.timeColumn, alignment: .trailing)
            Text(stop.name)
                .font(.system(size: row.step.size, weight: weight)).lineSpacing(max(0, row.step.lineHeight - natural))
                .lineLimit(row.step.lines).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(color)
        .padding(.horizontal, BraunDrum.rowPadding)
        .frame(width: layout.drum.width, height: row.slot.height)
        .background { if o == 0 { RoundedRectangle(cornerRadius: BraunDrum.pillRadius, style: .continuous).fill(pal.pill) } }
    }
}

// MARK: - Фигуры

/// Риски одного вида (пройденные / оставшиеся, обычные / часовые) по периметру: 150 штук от середины верха по часовой, риска по нормали внутрь,
/// внешний конец в 3 от края. Это `Shape`, а не `Canvas`: путь виджет архивирует как есть.
struct BraunTickLayer: Shape {
    let radius: Double
    let past: Bool
    let hour: Bool
    let duration: Double
    let elapsed: Double
    let hours: Set<Int>

    func path(in rect: CGRect) -> Path {
        let inset = BraunTicks.outerInset
        let walker = PerimeterWalker(rect: rect.insetBy(dx: inset, dy: inset), radius: CGFloat(radius - inset))
        let length = CGFloat(hour ? BraunTicks.hourLength : BraunTicks.minorLength)
        let half = CGFloat(hour ? BraunTicks.hourWidth : BraunTicks.minorWidth) / 2
        var path = Path()
        for i in 0..<BraunTicks.count {
            guard hours.contains(i) == hour, BraunTicks.isPast(index: i, duration: duration, elapsed: elapsed) == past else { continue }
            let (p, n) = walker.sample(CGFloat(i) / CGFloat(BraunTicks.count) * walker.length)
            // Концы скруглены (штрих с круглым краем): отступ на полширины с обеих сторон оставляет длину риски равной `length`.
            path.move(to: CGPoint(x: p.x + n.dx * half, y: p.y + n.dy * half))
            path.addLine(to: CGPoint(x: p.x + n.dx * (length - half), y: p.y + n.dy * (length - half)))
        }
        return path
    }
}

/// Точки часов одного состояния (горят / погасли): 60 на радиусе D/2 − 6, каждая пятая крупнее.
struct BraunDotLayer: Shape {
    let diameter: Double
    let minutes: Int
    let lit: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for k in 0..<BraunDial.dots where BraunDial.isLit(dot: k, minutesLeft: minutes) == lit {
            let s = BraunDial.dotSize(k), p = BraunDial.dotCenter(k, diameter: diameter)
            path.addEllipse(in: CGRect(x: c.x + p.x - s / 2, y: c.y + p.y - s / 2, width: s, height: s))
        }
        return path
    }
}

/// Флажок Braun слева от окошка: красный шеврон (острие вправо, V-вырез слева), красный в обеих темах (#ad0a15 / #c8102e).
struct BraunFlag: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let pts = BraunWindow.flagPoints(width: Double(r.width), height: Double(r.height))
        p.move(to: CGPoint(x: r.minX + pts[0].x, y: r.minY + pts[0].y))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: r.minX + q.x, y: r.minY + q.y)) }
        p.closeSubpath()
        return p
    }
}
