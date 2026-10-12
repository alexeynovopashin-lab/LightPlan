import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Числа полёта в корзину — один в один с `deleteToBin` беты (`beta/index.html:30152–30193`, стили `1822–1856`).
/// Меряно в Playwright на живой бете (iPhone-вьюпорт 430×932): `--tabh` 84 pt, `bottom` круга 110 pt, круг
/// выезжает с 120 pt, плашка достигает 0,05 ровно к моменту глотка, у круга пик 1,15 на 0,12 с, скрыт через 1,29 с.
enum BinTimeline {
    /// Круг `binTarget`: 56 pt, снизу `tabh + 26`, выезжает с 120 pt.
    static let size: CGFloat = 56
    /// `--tabh` (84, он же `TabBarView.height`, держит тест) + 26.
    static let lift: CGFloat = 84 + 26
    static let offscreen: CGFloat = 120
    /// Выезд круга, 0,34 с E1 (`cubic-bezier(0.25,1,0.4,1)`).
    static let rise: Double = 0.34
    /// Пауза между выездом и полётом.
    static let pause: Double = 0.2
    /// Полёт плашки: `scale(0.05)`, 0,42 с `cubic-bezier(0.55,0,0.85,0.35)`; прозрачность 0,42 с `ease-in`.
    static let flight: Double = 0.42
    static let flightScale: CGFloat = 0.05
    /// Глоток начинается через 0,43 с от начала полёта; в этот момент запись стёрта и показана «Вернуть».
    static let gulpAt: Double = 0.43
    /// `binGulp`: 1 → 1,16 (на 40 %) → 1 за 0,3 с, на каждом отрезке `ease-out`.
    static let gulp: Double = 0.3
    static let gulpPeak: CGFloat = 1.16
    static let gulpPeakAt: Double = 0.4
    /// Через 0,32 с после глотка круг уезжает (0,34 с), по окончании скрыт.
    static let leaveAfter: Double = 0.32
    static let hideAfter: Double = 0.34

    static let riseCurve = Animation.timingCurve(0.25, 1, 0.4, 1, duration: rise)
    static let flightCurve = Animation.timingCurve(0.55, 0, 0.85, 0.35, duration: flight)
    /// CSS `ease-in` = `cubic-bezier(0.42,0,1,1)`.
    static let fadeCurve = Animation.timingCurve(0.42, 0, 1, 1, duration: flight)
    /// CSS `ease-out` = `cubic-bezier(0,0,0.58,1)`.
    static func easeOut(_ d: Double) -> Animation { .timingCurve(0, 0, 0.58, 1, duration: d) }

    /// Моменты от начала (с): выезд 0, полёт и звук `pause`, глоток `pause + gulpAt`, уезд, скрытие.
    static var flyAt: Double { pause }
    static var gulpAtTotal: Double { pause + gulpAt }
    static var leaveAtTotal: Double { gulpAtTotal + leaveAfter }
    static var hideAtTotal: Double { leaveAtTotal + hideAfter }
}

/// Полёт плашки в корзину (29.7): движение и звук на любом стирании. Один компонент на всё приложение.
///
/// Порядок беты: круг выезжает снизу → пауза 0,2 с → плашка схлопывается в центр круга и звучит смятие →
/// на 0,43 с полёта глоток (запись стёрта, появляется «Вернуть») → круг уезжает. `Reduce Motion`: запись
/// стирается сразу, без звука (как `calm` беты).
///
/// Хранения стёртого здесь нет — только движение и звук; корзина мудборда съёмки лежит в подборке (`RefBin`, 29б).
@MainActor
@Observable
final class BinFlight {
    /// Где рисуется круг: поверх оболочки, в листе места или в листе корзины мудборда (29б).
    enum Host { case shell, place, mbBin }

    /// Круг в дереве (беты `!hidden`).
    private(set) var shown = false
    /// Круг на месте (беты `.up`).
    private(set) var up = false
    /// Плашки-цели схлопнуты в круг.
    private(set) var flying = false
    /// Значения «глотка»: размер контура и знака (стекло не масштабируют — двигают контур).
    private(set) var gulpScale: CGFloat = 1
    private(set) var host: Host = .shell
    private(set) var subjects: Set<String> = []
    /// Центр круга в координатах окна — точка, куда стягиваются плашки (пишет сам круг).
    var center: CGPoint = .zero
    private(set) var busy = false

    @ObservationIgnored private var runs = 0
    /// Номер полёта в процессе и сколько раз он сам позвал смятие: журналы (`BinLog`) помечают строки номером, тест
    /// читает только свой полёт — чужие стирания параллельных тестов в его журнал не попадают.
    @ObservationIgnored let id: Int = BinFlight.takeID()
    @ObservationIgnored private(set) var sounds = 0
    @ObservationIgnored nonisolated(unsafe) private static var lastID = 0
    private static func takeID() -> Int { lastID += 1; return lastID }

    /// Пересчёт «Уменьшить движение»: у системы или (тесты, стенд) свой ответ.
    static var reduceMotionOverride: Bool?
    static var reduceMotion: Bool {
        if let o = reduceMotionOverride { return o }
        #if canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled
        #elseif canImport(AppKit)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        return false
        #endif
    }

    /// Стирание с полётом. `subjects` — ключи плашек, что схлопываются (`binSubject`); `commit` стирает запись
    /// в момент глотка. Звук — один на стирание.
    func fly(subjects keys: Set<String> = [], host: Host = .shell, commit: @escaping () -> Void) {
        runs += 1
        let n = runs
        if Self.reduceMotion {
            BinLog.note(n, "calm", flight: id)
            commit()
            return
        }
        if busy {
            // Второе стирание поверх идущего полёта: запись уходит сразу, звук свой — одно смятие на стирание.
            BinLog.note(n, "busy", flight: id)
            sounds += 1
            SoundCenter.play(.trash, event: "binTrash")
            commit()
            return
        }
        busy = true
        self.host = host
        subjects = keys
        gulpScale = 1
        flying = false
        up = false
        shown = true
        SoundCenter.prepare()
        let t0 = ContinuousClock.now
        Task { @MainActor in
            func at(_ s: Double) async { try? await Task.sleep(until: t0 + .milliseconds(Int((s * 1000).rounded())), clock: .continuous) }
            BinLog.note(n, "rise", flight: id)
            withAnimation(BinTimeline.riseCurve) { up = true }
            await at(BinTimeline.flyAt)
            BinLog.note(n, "fly", flight: id)
            sounds += 1
            SoundCenter.play(.trash, event: "binTrash")
            // Глоток — когда плашка долетела: не раньше таймера беты (0,43 с) и не раньше, чем кончилась сама анимация
            // (в симуляторе она встаёт на ~2 кадра позже метки «fly»; без этого плашка стирается на 22 %, а не на 5 %).
            var landed = false
            withAnimation(BinTimeline.flightCurve, completionCriteria: .logicallyComplete) {
                flying = true
            } completion: { landed = true }
            await at(BinTimeline.gulpAtTotal)
            var spare = 0
            while !landed && spare < 12 { try? await Task.sleep(for: .milliseconds(8)); spare += 1 }
            BinLog.note(n, "gulp", flight: id)
            let g0 = ContinuousClock.now
            func after(_ s: Double) async { try? await Task.sleep(until: g0 + .milliseconds(Int((s * 1000).rounded())), clock: .continuous) }
            var tx = Transaction(); tx.disablesAnimations = true
            withTransaction(tx) { commit() }
            withAnimation(BinTimeline.easeOut(BinTimeline.gulpPeakAt * BinTimeline.gulp)) { gulpScale = BinTimeline.gulpPeak }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int((BinTimeline.gulpPeakAt * BinTimeline.gulp * 1000).rounded())))
                withAnimation(BinTimeline.easeOut((1 - BinTimeline.gulpPeakAt) * BinTimeline.gulp)) { gulpScale = 1 }
            }
            await after(BinTimeline.leaveAfter)
            BinLog.note(n, "leave", flight: id)
            withAnimation(BinTimeline.riseCurve) { up = false }
            await after(BinTimeline.leaveAfter + BinTimeline.hideAfter)
            BinLog.note(n, "hide", flight: id)
            withTransaction(tx) {
                shown = false
                flying = false
                subjects = []
                gulpScale = 1
            }
            busy = false
        }
    }
}

/// Тесты и стенд: свой ответ на «Уменьшить движение».
enum BinFlightControl {
    @MainActor static func calm(_ on: Bool) { BinFlight.reduceMotionOverride = on }
    @MainActor static func reset() { BinFlight.reduceMotionOverride = nil }
}

/// Журнал полёта (Debug, `-LPBinLog <файл>`; имя без «/» — файл в `Documents`): строка на фазу — время,
/// номер стирания, фаза (`rise`, `fly`, `gulp`, `leave`, `hide`; `calm` — без движения, `busy` — поверх полёта).
enum BinLog {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPBinLog").map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL.documentsDirectory.appending(path: $0)
    }
    /// Те же строки для тестов.
    @MainActor private(set) static var journal: [(run: Int, phase: String, at: TimeInterval, flight: Int)] = []
    @MainActor static func reset() { journal.removeAll() }
    #endif
    @MainActor static func note(_ run: Int, _ phase: String, flight: Int = 0) {
        #if DEBUG
        let t = ProcessInfo.processInfo.systemUptime
        journal.append((run, phase, t, flight))
        guard let url else { return }
        guard let data = String(format: "%.3f run=%d %@\n", t, run, phase).data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
}

extension BinLog {
    /// Значение, которое анимация отдала на этом кадре (`plate` — масштаб плашки, `gulp` — размер круга): строка в
    /// журнале на каждое изменение. Меряем числами, а не глазом (29.7).
    nonisolated static func sample(_ tag: String, _ v: Double) {
        #if DEBUG
        guard url != nil else { return }
        if lastSample[tag] == v { return }
        lastSample[tag] = v
        let t = ProcessInfo.processInfo.systemUptime
        guard let data = String(format: "%.3f sample %@ %.4f\n", t, tag, v).data(using: .utf8),
              let url else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
    #if DEBUG
    nonisolated(unsafe) private static var lastSample: [String: Double] = [:]
    #endif
}

/// Масштаб с отдачей кадров: `animatableData` получает промежуточное значение на каждом кадре анимации.
nonisolated private struct BinScale: ViewModifier, Animatable {
    var value: CGFloat
    var anchor: UnitPoint
    var tag: String
    var animatableData: CGFloat {
        get { value }
        set { value = newValue }
    }
    func body(content: Content) -> some View {
        BinLog.sample(tag, Double(value))
        return content.scaleEffect(value, anchor: anchor)
    }
}

/// Круг с размером контура `value` (стекло не масштабируют — меняют рамку): знак растёт вместе с ним.
nonisolated private struct BinGulpDisc: View, Animatable {
    var value: CGFloat
    var ink: Color
    var animatableData: CGFloat {
        get { value }
        set { value = newValue }
    }
    var body: some View {
        let _ = BinLog.sample("gulp", Double(value))
        ZStack {
            Color.clear
                .frame(width: BinTimeline.size * value, height: BinTimeline.size * value)
                .glassEffect(.regular, in: Circle())
            Icon("trash", size: 24, line: 1.6).foregroundStyle(ink).scaleEffect(value)
        }
    }
}

// MARK: - Круг

/// Круг `binTarget`: стекло 56 pt, знак корзины. «Глоток» меняет размер контура, а не масштаб стекла
/// (`glassEffect` под `scaleEffect` раздувается — 28п).
struct BinTarget: View {
    let flight: BinFlight
    let host: BinFlight.Host
    /// Расстояние от нижнего края до низа круга.
    var lift: CGFloat = BinTimeline.lift
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if flight.shown && flight.host == host {
            let pal = Palette(scheme)
            let slot = BinTimeline.size * BinTimeline.gulpPeak
            let g = flight.gulpScale
            ZStack {
                // Место круга в покое: сюда стягиваются плашки; не двигается и не растёт.
                Color.clear.frame(width: BinTimeline.size, height: BinTimeline.size)
                    .onGeometryChange(for: CGPoint.self) {
                        let f = $0.frame(in: .global); return CGPoint(x: f.midX, y: f.midY)
                    } action: { flight.center = $0 }
                BinGulpDisc(value: g, ink: pal.ink3)
                    .frame(width: slot, height: slot)
                .offset(y: flight.up ? 0 : BinTimeline.offscreen)
            }
            .frame(width: slot, height: slot)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, lift)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Плашка

/// Плашка, которая может улететь в корзину: сжимается в центр круга (`scale 0,05`, 0,42 с) и гаснет.
/// Ключ — id записи, подборки, кадра: тот, под которым экран зовёт `BinFlight.fly`.
private struct BinSubject: ViewModifier {
    let flight: BinFlight
    let key: String
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        let armed = flight.subjects.contains(key)
        let on = flight.flying && armed
        let c = flight.center
        let anchor = frame.width > 0 && frame.height > 0
            ? UnitPoint(x: (c.x - frame.minX) / frame.width, y: (c.y - frame.minY) / frame.height) : .center
        content
            // Кадр плашки снимается один раз — когда её назвали целью (круг выезжает, до полёта 0,2 с). Следить за
            // кадром всегда нельзя: у каждой строки списка это была бы запись состояния на каждый кадр прокрутки.
            .background {
                GeometryReader { g in
                    Color.clear.onChange(of: armed) { _, now in if now { frame = g.frame(in: .global) } }
                }
            }
            .modifier(BinScale(value: on ? BinTimeline.flightScale : 1, anchor: anchor, tag: "plate"))
            .animation(BinTimeline.flightCurve, value: on)
            .opacity(on ? 0 : 1)
            .animation(BinTimeline.fadeCurve, value: on)
    }
}

extension View {
    /// Плашка, улетающая в корзину при стирании (`BinFlight.fly(subjects:)`).
    func binSubject(_ app: AppModel, _ key: String) -> some View {
        modifier(BinSubject(flight: app.binFlight, key: key))
    }
}

extension AppModel {
    /// Стереть с полётом: круг выезжает, плашка `subjects` схлопывается в него, звучит смятие, в момент глотка
    /// `commit` стирает запись (и показывает «Вернуть», где она есть).
    func flyToBin(_ subjects: Set<String> = [], host: BinFlight.Host = .shell, commit: @escaping () -> Void) {
        binFlight.fly(subjects: subjects, host: host, commit: commit)
    }
}
