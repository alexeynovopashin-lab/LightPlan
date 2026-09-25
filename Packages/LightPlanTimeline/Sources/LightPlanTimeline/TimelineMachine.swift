import LightPlanCore

/// Итог одного шага жеста слайдера: что случилось с механизмом взвода и в
/// какую сторону, если он сорвался. `fired` — сутки уже сменились внутри
/// `TimelineMachine`, второй фазы (как в вебе «выезд → подмена → въезд») тут
/// нет: анимация выезда/въезда — дело UI (итерация 17), машина отдаёт только
/// факт и направление.
public enum TimelineOutcome: Sendable, Equatable {
    case idle
    case winding
    case fired(direction: Int)
}

/// Временная модель «Света» и «Карты»: выбранный день, минута, окно суток,
/// положение ленты и барабана, машина взвода и срыва. Ни одного `View` —
/// итог итерации 16 плана, чистая механика, которую итерация 17 подключает к
/// экрану.
///
/// Окно суток — `SolarDay.mint…maxt` того же дня (солнечная полночь; итерация
/// 7). Один слайдер и одна лента ходят по одному окну: в вебе слайдер стоит
/// на `MINT…MAXT`, а лента — на плоской шкале 0…1440 с отдельным клампом в
/// `MINT…MAXT` при письме (`ribbonApply`); здесь этого раздвоения нет
/// намеренно — обе стороны без клипа: реализация упрощена (корзина 2, § A.4
/// плана: наблюдение веба, а не замысел), окно суток то же самое, что дал бы
/// код и в такой мере расходится с вебом на секунды у долготы, где солнечный
/// полдень не совпадает с 12:00.
public struct TimelineMachine: Sendable, Equatable {

    private var place: Place

    public private(set) var selectedDate: CivilDate
    public private(set) var viewMinute: Minutes
    /// Окно текущих суток: солнечная полночь и следующая за ней (`SolarDay`).
    public private(set) var mint: Minutes
    public private(set) var maxt: Minutes

    public private(set) var ribbonMode: RibbonMode
    /// Смещение барабана в ячейках от выбранных суток. Между хватами всегда 0.
    public private(set) var drumOffset: Double = 0

    public private(set) var wind = Transmission()

    /// Направление последнего перехода через сутки, -1/0/+1 — веб `dayShift`.
    /// Потребляется ровно один раз: UI читает и сам решает, что анимировать
    /// (тот же приём, что в вебе — прочитал, обнулил, `index.html:19206`).
    public private(set) var dayShift = 0

    private var sliderHolding = false
    private var sliderLastX: Double?
    private var ribbonDragging = false
    private var ribbonLast: Double = 0

    /// Ячейка барабана и половина ширины ленты в третях экрана — те же числа,
    /// что в `Spikes/TimebarSpike` и в вебе.
    public static let drumCell = 50.0
    /// Сколько ячеек барабана видно по каждую сторону от выбранной.
    public static let drumSpan = 4

    public init(date: CivilDate, minute: Minutes? = nil, place: Place, ribbonMode: RibbonMode = .drum) {
        self.place = place
        self.selectedDate = date
        let day = SolarDay(date: date, place: place)
        self.mint = day.mint
        self.maxt = day.maxt
        self.viewMinute = TimelineMachine.clamp(minute ?? day.solarNoon, day.mint, day.maxt)
        self.ribbonMode = ribbonMode
    }

    private mutating func setDay(_ date: CivilDate) {
        selectedDate = date
        let day = SolarDay(date: date, place: place)
        mint = day.mint
        maxt = day.maxt
    }

    /// Место сменилось (геокодер, ручной выбор) — окно суток пересчитывается
    /// на тот же выбранный день.
    public mutating func setPlace(_ newPlace: Place) {
        place = newPlace
        setDay(selectedDate)
        viewMinute = Self.clamp(viewMinute, mint, maxt)
    }

    public mutating func setRibbonMode(_ mode: RibbonMode) {
        ribbonMode = mode
        drumOffset = 0
    }

    /// Направление последнего перехода, прочитанное и сброшенное — второй
    /// подряд вызов вернёт 0, пока не случится новый переход.
    public mutating func consumeDayShift() -> Int {
        defer { dayShift = 0 }
        return dayShift
    }

    // MARK: - Слайдер: передача разряда

    /// Палец ведёт слайдер. `x` — координата в дорожке, `width` — её ширина,
    /// `thumb` — ширина головки (для отступа по центру головки, как в вебе).
    /// Первый вызов после `endSliderDrag()` трактуется как взятие рукоятки.
    public mutating func dragSlider(x: Double, width: Double, thumb: Double) -> TimelineOutcome {
        if !sliderHolding {
            sliderHolding = true
            wind.grab()
        }
        guard !wind.spent else {
            sliderLastX = x
            return .idle
        }

        let usable = max(width - thumb, 1)
        let p = min(max((x - thumb / 2) / usable, 0), 1)
        viewMinute = Self.clamp(mint + p * (maxt - mint), mint, maxt)

        // Взвод начинается, только когда значение уже на упоре И палец
        // продолжает идти наружу в зоне у края.
        let atMax = viewMinute >= maxt - 0.5
        let atMin = viewMinute <= mint + 0.5
        let side = atMax && x > width - Transmission.edgeZone ? 1
                 : atMin && x < Transmission.edgeZone ? -1 : 0

        let dx = x - (sliderLastX ?? x)
        sliderLastX = x

        guard side != 0 else {
            // Ушли из зоны: ярус возвращается сразу (замысел, а не случайность
            // — Алексей, 20 сентября 2026). Стравливание накопленного — дело
            // вызывающего через `wind.bleed(from:k:)` по своему тикеру.
            wind.release()
            return .idle
        }
        switch wind.drag(dx: dx, side: side) {
        case .fire(let dir): return fireDay(dir)
        case .winding: return .winding
        case .idle: return .idle
        }
    }

    /// Упершийся палец двигать уже некуда — доводит удержанием. Вызывающий
    /// гонит это по своему тикеру (`CADisplayLink`), пока `sliderHolding`.
    public mutating func dwellSlider(dt: Double) -> TimelineOutcome {
        guard sliderHolding, !wind.spent else { return .idle }
        switch wind.dwell(dt: dt) {
        case .fire(let dir): return fireDay(dir)
        case .winding: return .winding
        case .idle: return .idle
        }
    }

    /// Рукоятку отпустили: следующий срыв снова доступен только после нового
    /// взятия.
    public mutating func endSliderDrag() {
        sliderHolding = false
        sliderLastX = nil
        wind.release()
    }

    /// Стравливание накопленного взвода — палец ушёл из зоны или отпустил, не
    /// дожав. Машина только хранит значение; тикер и кубическое затухание —
    /// дело вызывающего (итерация 16 сознательно оставила анимацию итерации
    /// 17: «UI подключает» в комментарии выше).
    public mutating func bleedWind(from w0: Double, progress k: Double) {
        wind.bleed(from: w0, k: k)
    }

    /// Стравливание закончилось — снять остаток.
    public mutating func resetWind() {
        wind.reset()
    }

    private mutating func fireDay(_ dir: Int) -> TimelineOutcome {
        wind.fired()
        setDay(selectedDate.adding(days: dir))
        // Встаём на противоположный край новых суток — как в вебе.
        viewMinute = dir > 0 ? mint : maxt
        dayShift = dir
        return .fired(direction: dir)
    }

    // MARK: - Лента и барабан

    /// Куда сдвинута дорожка ленты/барабана относительно клипа. Считается
    /// заново каждый раз из `(viewMinute, drumOffset)` — метка поэтому не
    /// может «поехать» сама по себе: лента едет, метка стоит (Core UX 5).
    public func ribbonOffset(clipWidth: Double) -> Double {
        switch ribbonMode {
        case .lane:
            // Сутки на дорожке — от полуночи (`buildRibbonDay`), вчера
            // первыми: под меткой — минута настенных часов, как у веба
            // (`ribbonCenterPx`). До 19б здесь вычиталось ещё начало окна
            // (`mint`) — лента отставала от ползунка на сдвиг солнечного
            // полдня: 77 минут в Барнауле.
            let pxPerMin = clipWidth / 1440
            return (1440 + viewMinute) * pxPerMin - clipWidth / 2
        case .drum:
            return (Double(Self.drumSpan) + drumOffset) * Self.drumCell + Self.drumCell / 2 - clipWidth / 2
        }
    }

    /// `translation` — накопленный сдвиг пальца от начала жеста (как
    /// `DragGesture.Value.translation`). Начало жеста ловится здесь, а не
    /// отдельным «взяли»: SwiftUI не обещает нулевой первый кадр.
    @discardableResult
    public mutating func dragRibbon(translation: Double, clipWidth: Double) -> Int {
        if !ribbonDragging {
            ribbonDragging = true
            ribbonLast = translation
        }
        let dx = translation - ribbonLast
        ribbonLast = translation
        switch ribbonMode {
        case .lane:
            // Окно суток всегда 1440 минут, масштаб тот же, что у дорожки.
            let pxPerMin = clipWidth / 1440
            return wallFlip(delta: -dx / pxPerMin)
        case .drum:
            return drumFlip(delta: -dx / Self.drumCell)
        }
    }

    public mutating func endRibbonDrag() {
        ribbonDragging = false
        ribbonLast = 0
    }

    /// Шаг стрелками/колесом на ленте, минуты (веб: `e.shiftKey ? 60 : 15`).
    public static let arrowStep: Minutes = 15
    public static let arrowStepShift: Minutes = 60

    /// Стрелки/колесо на ленте (`lane`): двигают минуту напрямую.
    @discardableResult
    public mutating func stepViewMinute(by delta: Minutes) -> Int {
        wallFlip(delta: delta)
    }

    /// Стрелки/колесо на барабане (`drum`): двигают только сутки, время суток
    /// не трогают вовсе — как тап по соседней ячейке.
    @discardableResult
    public mutating func tapDrumCell(offset: Int) -> Int {
        guard offset != 0 else { return 0 }
        setDay(selectedDate.adding(days: offset))
        drumOffset = Double(offset)
        dayShift = offset
        return offset
    }

    /// Осадка барабана после отпускания без тапа: цель всегда 0, доводит её
    /// анимацией вызывающий (итерация 17). Возвращает, откуда доводить.
    public mutating func settleDrum() -> Double {
        let from = drumOffset
        drumOffset = 0
        return from
    }

    /// Переход через границу суток на ленте — сразу, без порога и паузы
    /// (DECISIONS, «Лента без нативного скролла»): читать обратно нечего,
    /// нечему рассинхронизироваться. Сдвиг между днями — фиксированные 1440
    /// минут, как в вебе (`t -= dir·1440`), а не разница новых и старых
    /// границ: следующий кадр укладывает минуту в свежие `mint…maxt` сам.
    @discardableResult
    private mutating func wallFlip(delta: Minutes) -> Int {
        viewMinute += delta
        var shift = 0
        while viewMinute < mint || viewMinute >= maxt {
            let dir = viewMinute < mint ? -1 : 1
            setDay(selectedDate.adding(days: dir))
            viewMinute -= Double(dir) * 1440
            shift += dir
        }
        if shift != 0 { dayShift = shift }
        return shift
    }

    /// Барабан крутит только сутки: младший разряд не трогает старший, пока
    /// сам не переполнится.
    @discardableResult
    private mutating func drumFlip(delta: Double) -> Int {
        drumOffset += delta
        var shift = 0
        while drumOffset < -0.5 || drumOffset > 0.5 {
            let dir = drumOffset > 0 ? 1 : -1
            setDay(selectedDate.adding(days: dir))
            drumOffset -= Double(dir)
            shift += dir
        }
        if shift != 0 { dayShift = shift }
        return shift
    }

    // MARK: - Купол и выбор момента (итерация 19в)

    /// Палец ведёт светило по куполу (`domeDrag` → `setView` веба): минута
    /// внутри тех же суток, день не меняется — купол, как и ползунок, за
    /// окно `mint…maxt` не выходит.
    public mutating func setViewMinute(_ minute: Minutes) {
        viewMinute = Self.clamp(minute, mint, maxt)
    }

    /// Момент из листа «Когда смотрим»: день и время суток по часам места.
    /// Окно суток начинается солнечной полночью, а не 00:00, и время у самой
    /// полуночи ему может не принадлежать (00:10 при `mint` = 00:30). Такое
    /// время отходит к соседним суткам, а минута — та, что выбрана: экран
    /// покажет выбранный день. Веб в этом случае прибавляет 1440 к тем же
    /// суткам и показывает следующий день (DECISIONS, 19в).
    @discardableResult
    public mutating func show(day: CivilDate, minute: Minutes) -> Int {
        let from = selectedDate
        setDay(day)
        drumOffset = 0
        viewMinute = minute
        while viewMinute < mint || viewMinute >= maxt {
            let dir = viewMinute < mint ? -1 : 1
            setDay(selectedDate.adding(days: dir))
            viewMinute -= Double(dir) * 1440
        }
        let dir = selectedDate == from ? 0 : (selectedDate > from ? 1 : -1)
        if dir != 0 { dayShift = dir }
        return dir
    }

    // MARK: - «Сейчас»

    /// Прыжок к настоящему моменту (кнопка «↺ сейчас»). `today`/`minute` уже
    /// посчитаны вызывающим (`WallTime(moment:utcOffsetHours:)` в зоне
    /// места) — машина не трогает системные часы напрямую, чтобы сценарий
    /// проверялся числами, а не `Date()`.
    @discardableResult
    public mutating func jumpToNow(day today: CivilDate, minute: Minutes) -> Int {
        let dir = today == selectedDate ? 0 : (today > selectedDate ? 1 : -1)
        if dir != 0 {
            setDay(today)
            dayShift = dir
        }
        viewMinute = Self.clamp(minute, mint, maxt)
        drumOffset = 0
        return dir
    }

    private static func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double {
        min(max(v, a), b)
    }
}
