import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Один слой отдачи (29.5): карта «событие → тип» и одно место, откуда уходит тик.
///
/// У беты на iPhone один системный тик на касание (`hapticize`: вкладки, сегменты,
/// кнопка и веер видов, закладка карты, `sky-swap`, дата ленты дня); `navigator.vibrate`
/// в Safari нет, прочие вибрации беты — Android. Правило слоя: переключателям —
/// `selection`, акцентам — `light`, булавке и подтверждению — `medium`. Отдача гасится
/// системной настройкой «Haptics» iOS сама: своего переключателя нет. Reduce Motion к
/// ней не относится (это не движение).
///
/// Звук (29.6): у события в карте есть `sound`; `play` отдаёт тик и щелчок одним вызовом. Таймбар звучит из
/// `TimebarHaptics.detent` тем же образом — один источник.
///
/// Не через слой — отдача таймбара (`Timebar/TimebarHaptics`, свой CoreHaptics-слой,
/// подтверждён на телефоне). Через неё же ходит и купол: час под пальцем — детент
/// таймбара (`TimebarState.dragDome` → `checkHourMark`), второго тика слой не ставит.
enum HapticKind: String, CaseIterable, Sendable {
    case selection, light, medium, heavy
}

/// События. Имена — по смыслу, а не по месту в коде: новое место зовёт готовое событие.
enum HapticEvent: String, CaseIterable, Sendable {
    // Были в нативе до 29.5 — тип и сила перенесены без изменений.
    /// Долгое нажатие на жанр в форме.
    case genreHold
    /// Метка шкалы срока сдачи (`DeadlineDial`).
    case deadlineStop
    /// Веер над записью на ленте дня.
    case fan
    /// Подъём события на ленте дня (жест `DayGrip`).
    case dayLift
    /// Шаг времени под пальцем на ленте дня.
    case dayNotch
    /// Подъём блока карточки в «ползунках».
    case cardBlockLift
    /// Подъём точки маршрута на карте.
    case routePointLift
    /// Булавка поставлена или сохранена.
    case spotDrop
    /// Центр компаса стал визиром или вернулся в круг.
    case sight

    // Новые в 29.5 (H1: у беты на iPhone есть `hapticize`).
    case tab
    case segment
    /// Кнопка вида в шапке «Съёмок».
    case scopeButton
    /// Строка веера видов.
    case scopeItem
    /// Закладка карты: тап, который место убирает (когда ставит — `spotDrop`, один тик на касание).
    case mapSave
    case skySwap
    /// Тап по дате ленты дня.
    case dayStripDate

    // Новые в 29.5 (H2).
    /// Смена дня свайпом.
    case daySwipe
    /// Точка ленты точек плитки дня сменила колонку под пальцем.
    case laneDot
    /// Удержание кадра в папке мудборда — лист кадра (веб `23100`).
    case mbHold
    /// Удержание обложки в папке — выбор обложки (веб `23200`).
    case mbCover

    // Мудборд: сортировка подборок (29.3б, `MbSortDrag`); драг кадров в папке (29.3в, `MbFrameDrag`).
    /// Вход в режим сортировки (веб `21430`).
    case mbSortOn
    /// Плитка поднята (веб `21556`).
    case mbSortLift
    /// Плитка перешла в другую ячейку (веб `21606`).
    case mbSortZone
    /// Порядок подборок записан (веб `21707`).
    case mbSortSaved
    /// Кадр поднят в папке (веб `21817`).
    case mbFrameLift
    /// Кадр опущен на новое место (веб `21871`).
    case mbFrameDrop

    // Хвост 29.6а.
    /// Смена суток на барабане таймбара (веб `drumDayFlip` → `swoosh()`): тик и затвор, один на вызов.
    case timebarDayFlip

    // Новое в 29.3г: у беты свайпа по строке нет — тик по обычаю iOS.
    /// Свайп влево по строке съёмки раскрыл кнопку «Удалить».
    case rowReveal

    var kind: HapticKind {
        switch self {
        case .genreHold, .spotDrop, .sight: .medium
        case .deadlineStop, .dayNotch, .cardBlockLift, .routePointLift, .tab, .segment, .scopeButton, .scopeItem,
             .mapSave, .skySwap, .dayStripDate, .daySwipe, .laneDot, .mbSortZone, .rowReveal: .selection
        case .fan, .dayLift, .mbHold, .mbCover, .mbSortOn, .mbSortLift, .mbFrameLift, .timebarDayFlip: .light
        case .mbSortSaved, .mbFrameDrop: .medium
        }
    }

    /// Щелчок, что звучит вместе с тиком (29.6): ровно те места, где у беты стоит `tickClick()`, а не системный
    /// `hapticize`. Вкладки, сегменты, кнопка и веер видов, закладка карты, светило, булавка, визир, жанр, блок
    /// карточки и мудборд у беты звука не имеют (там тик касания или вибрация Android) — здесь тоже тихи.
    var sound: SoundCue? {
        switch self {
        case .deadlineStop,        // срок сдачи `fDelvDial` (веб 20400)
             .fan,                 // открытие веера над записью (35972); из подъёма он открывается молча (`quiet`)
             .dayLift, .dayNotch,  // подъём и сдвиг блока и ручки на ленте дня (19470, 19478, 19525)
             .routePointLift,      // удержание строки маршрута `rbHold` (16938)
             .dayStripDate,        // тап по дате ленты, только если день сменился (18835) — решает вызов
             .daySwipe,            // смена дня свайпом, только «день» (34397)
             .laneDot:             // точка ленты маршрута карточки (28920)
            .click
        case .timebarDayFlip:      // `swoosh()` в `drumDayFlip` (32248): затвор, не щелчок
            .shutter
        default: nil
        }
    }

    /// События, которых в нативе пока нет жестом. Сортировка подборок подключена в 29.3б, драг кадров в 29.3в — сейчас
    /// таких нет; свойство читает `SoundTests`, и новое зарезервированное событие встанет сюда.
    var awaitsGesture: Bool { false }
}

@MainActor
enum Haptics {

    /// Что отдаёт не слой, а таймбар: имя места беты → кто его закрывает. Тест держит перечень полным.
    static let ownedByTimebar: [String: String] = [
        "dome.hour": "TimebarState.dragDome → checkHourMark → TimebarHaptics.detent",
    ]

    /// Смена дня свайпом тикает только в «дне»: у беты `tickClick()` стоит в ветке `calScope === "day"` функции
    /// `stepCal`, у недели и месяца отдачи нет.
    static func daySwipeTicks(in scope: CalScope) -> Bool { scope == .day }

    /// `sound: false` — тик без щелчка: у даты ленты тик на каждое касание, а `tickClick` беты — только когда
    /// день сменился (`if (dayShift)`).
    static func play(_ event: HapticEvent, sound: Bool = true) {
        HapticsLog.note("\(event.rawValue) \(event.kind.rawValue)")
        #if os(iOS)
        generators.fire(event.kind)
        #endif
        // Один вызов — и тик, и щелчок: рассинхрона между ними быть не может.
        if sound, let cue = event.sound { SoundCenter.play(cue, event: event.rawValue) }
    }

    /// Прогреть движок до касания: первый тик после паузы иначе приходит с задержкой.
    static func prepare() {
        #if os(iOS)
        generators.prepareAll()
        #endif
        SoundCenter.prepare()
    }

    #if os(iOS)
    private static let generators = Generators()

    @MainActor
    private final class Generators {
        private let selection = UISelectionFeedbackGenerator()
        private let light = UIImpactFeedbackGenerator(style: .light)
        private let medium = UIImpactFeedbackGenerator(style: .medium)
        private let heavy = UIImpactFeedbackGenerator(style: .heavy)

        init() { prepareAll() }

        func prepareAll() {
            selection.prepare(); light.prepare(); medium.prepare(); heavy.prepare()
        }

        func fire(_ kind: HapticKind) {
            switch kind {
            case .selection: selection.selectionChanged(); selection.prepare()
            case .light: light.impactOccurred(); light.prepare()
            case .medium: medium.impactOccurred(); medium.prepare()
            case .heavy: heavy.impactOccurred(); heavy.prepare()
            }
        }
    }
    #endif
}

extension View {
    /// Тик события, когда `trigger` сменился (и `when` не против). Замена `.sensoryFeedback`:
    /// тип берётся из карты, журнал видит каждый вызов.
    func haptic<T: Equatable>(_ event: HapticEvent, trigger: T, when: ((T, T) -> Bool)? = nil) -> some View {
        onChange(of: trigger) { old, new in
            if when?(old, new) ?? true { Haptics.play(event) }
        }
    }
}

/// Журнал отдачи (Debug, `-LPHapticLog <файл>`; имя без «/» — файл в `Documents` приложения):
/// строка на вызов слоя — время (с загрузки), событие, тип. На симуляторе Taptic нет — меряем журнал.
enum HapticsLog {
    #if DEBUG
    nonisolated(unsafe) static let url = UserDefaults.standard.string(forKey: "LPHapticLog").map {
        $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL.documentsDirectory.appending(path: $0)
    }
    #endif
    static func note(_ line: @autoclosure () -> String) {
        #if DEBUG
        guard let url, let data = (String(format: "%.3f ", ProcessInfo.processInfo.systemUptime) + line() + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
        #endif
    }
}
