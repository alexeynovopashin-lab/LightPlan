import Testing
@testable import LightPlanUI

/// Карта «событие → тип» слоя отдачи (29.5): полнота и неизменность типов у перенесённых точек.
@MainActor
struct HapticsTests {

    /// Типы, что стояли в нативе до слоя (`git show 9270a73:<файл>`): тип и сила не меняются.
    private static let carried: [(HapticEvent, HapticKind, String)] = [
        (.genreHold, .medium, "FormGenres.swift:39 .impact(weight: .medium)"),
        (.deadlineStop, .selection, "FormMoney.swift:407 .selection"),
        (.fan, .light, "PlannerLayers.swift:121 .impact(weight: .light)"),
        (.dayLift, .light, "PlannerDayGrip.swift:75 UIImpactFeedbackGenerator(.light)"),
        (.dayNotch, .selection, "PlannerDayGrip.swift:76 UISelectionFeedbackGenerator"),
        (.cardBlockLift, .selection, "CardOrderList.swift:174 .selection"),
        (.routePointLift, .selection, "MapRouteViews.swift:357 .selection"),
        (.spotDrop, .medium, "MapScreenView.swift:348 .impact(weight: .medium)"),
        (.sight, .medium, "MapScreenView.swift:358 .impact(weight: .medium)"),
    ]

    /// События § 10 H1 и H2 аудита 29.1 — каждое названо в карте.
    private static let required: [HapticEvent] = [
        // H1
        .tab, .segment, .scopeItem, .scopeButton, .mapSave, .skySwap, .dayStripDate,
        // H2: смена дня свайпом, лента точек, мудборд (8 мест беты: сортировка вкл., подъём, зона, запись, кадр поднят,
        // кадр опущен, удержание кадра, удержание обложки)
        .daySwipe, .laneDot,
        .mbSortOn, .mbSortLift, .mbSortZone, .mbSortSaved, .mbFrameLift, .mbFrameDrop, .mbHold, .mbCover,
        // 29.3г: свайп по строке съёмки раскрыл «Удалить» — тик выбора (у беты жеста нет, обычай iOS).
        .rowReveal,
        // 29.6а: смена суток на барабане таймбара — `swoosh()` беты, затвор.
        .timebarDayFlip,
        // 29.8в.22: строка барабана «Когда смотрим» — тик выбора.
        .wheelRow,
    ]

    @Test func carriedTypesDoNotChange() {
        for (event, kind, was) in Self.carried {
            #expect(event.kind == kind, "\(event) был \(was)")
        }
    }

    @Test func everyRequiredEventIsMapped() {
        for e in Self.required { #expect(HapticEvent.allCases.contains(e)) }
        #expect(HapticEvent.allCases.count == Self.carried.count + Self.required.count)
    }

    @Test func eventsAreUnique() {
        #expect(Set(HapticEvent.allCases.map(\.rawValue)).count == HapticEvent.allCases.count)
    }

    @Test func switchesTickWithSelection() {
        for e: HapticEvent in [.tab, .segment, .scopeButton, .scopeItem, .mapSave, .skySwap, .dayStripDate, .daySwipe, .laneDot,
                               .rowReveal, .wheelRow] {
            #expect(e.kind == .selection, "\(e)")
        }
    }

    @Test func daySwipeTicksOnlyInDayScope() {
        for s in CalScope.allCases { #expect(Haptics.daySwipeTicks(in: s) == (s == .day), "\(s)") }
        #expect(!Haptics.daySwipeTicks(in: .week))
        #expect(!Haptics.daySwipeTicks(in: .month))
    }

    @Test func domeHourBelongsToTimebar() {
        #expect(Haptics.ownedByTimebar["dome.hour"] != nil)
    }

    /// 29.3б подключила сортировку подборок, 29.3в — драг кадров в папке: жеста, которого ждёт событие, не осталось.
    @Test func noMoodboardEventAwaitsAGestureAfterBothSteps() {
        let waiting = Set(HapticEvent.allCases.filter(\.awaitsGesture))
        #expect(waiting.isEmpty, "\(waiting)")
    }

    /// Вибрации беты 12 / 14 / 5 / 20 мс → лёгкий, лёгкий, выбор, средний; звука у мудборда нет.
    @Test func sortEventsKeepBetaWeights() {
        #expect(HapticEvent.mbSortOn.kind == .light)
        #expect(HapticEvent.mbSortLift.kind == .light)
        #expect(HapticEvent.mbSortZone.kind == .selection)
        #expect(HapticEvent.mbSortSaved.kind == .medium)
        for e in [HapticEvent.mbSortOn, .mbSortLift, .mbSortZone, .mbSortSaved] { #expect(e.sound == nil, "\(e)") }
    }

    /// Вибрации беты 16 / 20 мс (`mbFrameLift` / `mbFrameDrop`) → лёгкий и средний; звука у мудборда нет.
    @Test func frameEventsKeepBetaWeights() {
        #expect(HapticEvent.mbFrameLift.kind == .light)
        #expect(HapticEvent.mbFrameDrop.kind == .medium)
        #expect(HapticEvent.mbFrameLift.sound == nil && HapticEvent.mbFrameDrop.sound == nil)
    }
}
