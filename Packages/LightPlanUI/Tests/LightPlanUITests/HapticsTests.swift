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
        for e: HapticEvent in [.tab, .segment, .scopeButton, .scopeItem, .mapSave, .skySwap, .dayStripDate, .daySwipe, .laneDot] {
            #expect(e.kind == .selection, "\(e)")
        }
    }

    @Test func domeHourBelongsToTimebar() {
        #expect(Haptics.ownedByTimebar["dome.hour"] != nil)
    }

    @Test func reservedEventsAreExactlyTheSixMoodboardGestures() {
        let waiting = Set(HapticEvent.allCases.filter(\.awaitsGesture))
        #expect(waiting == [.mbSortOn, .mbSortLift, .mbSortZone, .mbSortSaved, .mbFrameLift, .mbFrameDrop])
    }
}
