import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Числа полёта обложки в папку — `openBoardWithFly` беты (`beta/index.html:21941–21975`, стиль `.mb-fly` L4028).
enum MbFlyTimeline {
    /// Полёт: `left/top/width/height/borderRadius` за 430 мс `cubic-bezier(.22,1,.36,1)`, `fill: forwards`.
    static let flight: Double = 0.43
    static let curve = Animation.timingCurve(0.22, 1, 0.36, 1, duration: flight)
    /// Гашение после посадки: `opacity 1 → 0` за 140 мс, кривая по умолчанию (`linear`).
    static let fade: Double = 0.14
    static let fadeCurve = Animation.linear(duration: fade)
    /// Подчистка: клон снимается через 900 мс от старта, даже если анимация не кончилась (вкладка в фоне, экран
    /// сменился под ним — у веба клон оставался лежать поверх всего с z-index 9999).
    static let sweep: Double = 0.9
    /// Скругление: у плитки 12, у шапки папки 14.
    static let radiusFrom: CGFloat = 12
    static let radiusTo: CGFloat = 14
    /// Тень `.mb-fly`: `0 4px 14px rgba(0,0,0,.18)`.
    static let shadowOpacity: Double = 0.18
}

/// Полёт обложки в шапку папки (29.3в, M5): тап по плитке подборки открывает папку, а обложка летит от плитки к
/// шапке (58 × 58) и гаснет. Один компонент на приложение, по образцу `BinFlight`.
///
/// Клон — тот же вид, что покажет шапка (у веба — одна картинка, не мозаика: мозаика из четырёх кадров не может
/// морфнуть в один квадрат). В нативе обложки пока без фото — заливка неба и знак жанра (28, шаг 5д, «Не сделано»),
/// поэтому летит она и летит всегда; у веба без картинки полёта нет (клону нечего показать).
/// Клон меняет рамку, а не масштаб: стекло под `scaleEffect` раздувается (28п), и правило одно на всех.
///
/// Отход от беты: веб снимает место шапки на первом кадре, когда папка ещё за нижним краем экрана (въезжает 0,42 с),
/// и клон летит туда — вниз за экран (замер Playwright 13.10: конец полёта y 1003 при экране 932; шапка встаёт на
/// y 62). Здесь цель — шапка на своём месте, как задумано в комментарии беты («обложка летит в шапку папки»).
/// Пока клон в полёте, шапка скрыта; клон сел — шапка видна, клон гаснет поверх неё.
@MainActor
@Observable
final class MbFly {
    /// Папка, в которую летит обложка (`nil` — клона нет).
    private(set) var board: String?
    private(set) var genre: String?
    /// Откуда: квадрат обложки плитки в координатах окна.
    private(set) var from: CGRect = .zero
    /// Куда: шапка папки на своём месте в покое, в координатах окна (пишет сама шапка; до первой раскладки — `nil`).
    private(set) var target: CGRect?
    /// Ход полёта 0 → 1 (кривая беты); рамка клона — от `from` к `target`.
    private(set) var k: Double = 0
    private(set) var opacity: Double = 1
    /// Клон сел: шапка снова видна, клон гаснет.
    private(set) var landed = false

    /// Квадраты обложек плиток на экране (полоса, галерея, полка), по id подборки. Без наблюдения: рамки меняются
    /// каждый кадр прокрутки.
    @ObservationIgnored var sources: [String: CGRect] = [:]
    @ObservationIgnored private var run = 0
    /// «Уменьшение движения»: у системы (`PlanMotion.still`) или свой ответ теста — общий флаг гоняли бы параллельные наборы.
    @ObservationIgnored var still: () -> Bool = { PlanMotion.still }
    /// Анимация с отметкой конца. Тест подставляет ту, что не кончается никогда (вкладка ушла в фон): клон должна
    /// снять подчистка.
    @ObservationIgnored var animate: (Animation, () -> Void, @escaping () -> Void) -> Void = { a, body, done in
        withAnimation(a, completionCriteria: .logicallyComplete, body, completion: done)
    }
    /// Номер полёта в процессе: тест читает журнал только своего полёта.
    @ObservationIgnored let id: Int = MbFly.takeID()
    @ObservationIgnored nonisolated(unsafe) private static var lastID = 0
    private static func takeID() -> Int { lastID += 1; return lastID }

    /// Шапка этой папки спрятана: клон ещё летит к ней.
    func hidesHero(_ boardId: String) -> Bool { board == boardId && !landed }

    /// Шапка папки сообщает своё место (на каждой раскладке).
    func hero(_ boardId: String, _ rect: CGRect) {
        guard board == boardId, rect.width > 0, rect != target else { return }
        target = rect
        MbFlyLog.note(run, "hero x=\(f(rect.minX)) y=\(f(rect.minY)) w=\(f(rect.width)) k=\(String(format: "%.3f", k))", flight: id)
    }

    /// Открыть папку с полётом. `open` открывает её (слой въезжает как раньше); без места плитки или при
    /// «Уменьшении движения» — только `open` (веб: `reduced` → `openMbFolder` сразу).
    func launch(board boardId: String, genre: String?, open: () -> Void) {
        run += 1
        let n = run
        guard !still() else { MbFlyLog.note(n, "calm", flight: id); clear(); open(); return }
        guard let src = sources[boardId], src.width > 0, src.height > 0 else {
            MbFlyLog.note(n, "nosource", flight: id); clear(); open(); return
        }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            board = boardId; self.genre = genre; from = src; target = nil; k = 0; opacity = 1; landed = false
        }
        MbFlyLog.note(n, "launch x=\(f(src.minX)) y=\(f(src.minY)) w=\(f(src.width))", flight: id)
        open()
        // Как у веба: полёт начинается со следующего кадра (`requestAnimationFrame`), когда папка разложена.
        DispatchQueue.main.async { [weak self] in
            guard let self, n == self.run, self.board != nil else { return }
            MbFlyLog.note(n, "fly", flight: self.id)
            self.animate(MbFlyTimeline.curve, { self.k = 1 }) { [weak self] in self?.land(n) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + MbFlyTimeline.sweep) { [weak self] in
            guard let self, n == self.run, self.board != nil else { return }
            MbFlyLog.note(n, "sweep", flight: self.id)
            self.clear()
        }
    }

    private func land(_ n: Int) {
        guard n == run, board != nil, !landed else { return }
        landed = true
        MbFlyLog.note(n, "land", flight: id)
        animate(MbFlyTimeline.fadeCurve, { self.opacity = 0 }) { [weak self] in
            guard let self, n == self.run, self.board != nil else { return }
            MbFlyLog.note(n, "gone", flight: self.id)
            self.clear()
        }
    }

    private func clear() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { board = nil; target = nil; k = 0; opacity = 1; landed = false }
    }

    /// Рамка клона на ходу `k`: прямая от плитки к шапке, как `left/top/width/height` веба.
    static func rect(from a: CGRect, to b: CGRect?, k: Double) -> CGRect {
        guard let b else { return a }
        let t = CGFloat(k)
        return CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                      width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    static func radius(k: Double) -> CGFloat {
        MbFlyTimeline.radiusFrom + (MbFlyTimeline.radiusTo - MbFlyTimeline.radiusFrom) * CGFloat(k)
    }

    private func f(_ v: CGFloat) -> String { String(format: "%.1f", Double(v)) }
}

/// Журнал полёта (Debug, `-LPMbFlyLog <файл>`; имя без «/» — файл в `Documents`): фазы (`launch`, `fly`, `land`,
/// `gone`; `sweep` — подчистка по таймеру, `calm` — без полёта, `nosource` — плитки нет на экране), место шапки и
/// по кадрам рамка клона (`clone`).
enum MbFlyLog {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPMbFlyLog").map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL.documentsDirectory.appending(path: $0)
    }
    /// Те же фазы для тестов.
    @MainActor private(set) static var journal: [(run: Int, phase: String, at: TimeInterval, flight: Int)] = []
    @MainActor static func reset() { journal.removeAll() }
    nonisolated(unsafe) private static var handle: FileHandle?
    #endif

    @MainActor static func note(_ run: Int, _ line: String, flight: Int = 0) {
        #if DEBUG
        let t = ProcessInfo.processInfo.systemUptime
        journal.append((run, String(line.split(separator: " ").first ?? ""), t, flight))
        write(String(format: "%.3f run=%d ", t, run) + line)
        #endif
    }

    nonisolated static func frame(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard url != nil else { return }
        write(String(format: "%.3f ", ProcessInfo.processInfo.systemUptime) + line())
        #endif
    }

    #if DEBUG
    nonisolated private static func write(_ line: String) {
        guard let url, let data = (line + "\n").data(using: .utf8) else { return }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            handle = try? FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
        }
        handle?.write(data)
    }
    #endif
}

// MARK: - Клон

/// Слой клона над всеми слоями оболочки, в координатах окна (`RootView`, `.ignoresSafeArea()`).
struct MbFlyLayer: View {
    let fly: MbFly

    var body: some View {
        if let id = fly.board {
            MbFlyClone(k: fly.k, from: fly.from, to: fly.target, boardId: id, genre: fly.genre)
                .opacity(fly.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Клон обложки на ходу `k`: рамка и скругление, тень `.mb-fly`. Пишет в журнал каждый кадр.
private struct MbFlyClone: View, @preconcurrency Animatable {
    var k: Double
    let from: CGRect
    let to: CGRect?
    let boardId: String
    let genre: String?
    var animatableData: Double {
        get { k }
        set { k = newValue }
    }

    var body: some View {
        let r = MbFly.rect(from: from, to: to, k: k)
        let rad = MbFly.radius(k: k)
        let _ = MbFlyLog.frame(String(format: "clone k=%.4f x=%.1f y=%.1f w=%.1f h=%.1f r=%.2f%@", k, r.minX, r.minY, r.width,
                                      r.height, rad, to == nil ? " notarget" : ""))
        MbCover(boardId: boardId, genre: genre, radius: rad)
            .shadow(color: .black.opacity(MbFlyTimeline.shadowOpacity), radius: 7, y: 4)
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
    }
}

extension View {
    /// Плитка подборки, из которой может взлететь обложка: квадрат обложки (верх плитки, сторона — её ширина).
    func mbFlySource(_ app: AppModel, _ boardId: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
            app.mbFly.sources[boardId] = CGRect(x: f.minX, y: f.minY, width: f.width, height: f.width)
        }
    }
}

extension AppModel {
    /// Тап по плитке подборки: полка с несколькими папками — полка (без полёта), папка — полёт обложки и папка
    /// (веб `openFolderOrShelf` → `openBoardWithFly`). Лента, галерея и полка ведут себя одинаково.
    func openMbFolderFlying(_ f: MbFolder) {
        switch Moodboard.openTarget(f, in: mbLibrary()) {
        case .shelf(let g): withAnimation(overlaySlide) { openMbShelf(g) }
        case .folder(let id): flyIntoMbFolder(id)
        }
    }

    /// Папка с полётом обложки (плитка папки на полке и путь выше). Клон — вид шапки: жанр папки.
    func flyIntoMbFolder(_ boardId: String) {
        let genre = mbLibrary().board(boardId).flatMap(mbFolderGenre)
        mbFly.launch(board: boardId, genre: genre) { withAnimation(overlaySlide) { openMbFolder(boardId: boardId) } }
    }
}
