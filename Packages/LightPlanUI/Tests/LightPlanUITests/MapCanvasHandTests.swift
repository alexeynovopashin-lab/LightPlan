import Testing
@testable import LightPlanMapCanvas
#if canImport(MapLibre)
import MapLibre
#endif

/// Итерация 20е: переезд камеры к булавке — программа, не палец; полоса
/// имени закрывается только от протяжки. На телефоне MapKit принимал любой
/// переезд за жест: центр возвращается с шумом в девятом знаке. Живой тап по
/// булавке на обоих холстах — `Tools/tap_spot.js`.
struct MapCanvasHandTests {

    private let placed = MapCanvasCenter(latitude: 53.3572, longitude: 83.774)

    @Test func mapKitNoiseIsNotHand() {
        // Замер 20е: MapKit отдал 53.354800002 при поставленных 53.3548.
        let echo = MapCanvasCenter(latitude: 53.3572 + 2e-9, longitude: 83.774 + 1e-9)
        #expect(!MapKitCanvas.byHand(echo, placed: placed))
        #expect(!MapKitCanvas.byHand(placed, placed: placed))
    }

    @Test func mapKitDragIsHand() {
        // Одна точка экрана на уровне 14 у 53° — около 3 м, 2,6e-5° широты.
        let dragged = MapCanvasCenter(latitude: 53.3572 + 2.6e-5, longitude: 83.774)
        #expect(MapKitCanvas.byHand(dragged, placed: placed))
        #expect(MapKitCanvas.byHand(dragged, placed: nil))
    }

    #if canImport(MapLibre)
    @Test func mapLibreReasons() {
        typealias C = MapLibreCanvas.Coordinator
        #expect(!C.byHand(.programmatic))
        #expect(!C.byHand([.programmatic, .gesturePan]))
        #expect(!C.byHand([]))
        #expect(C.byHand(.gesturePan))
        #expect(C.byHand(.gesturePinch))
        #expect(C.byHand([.gesturePan, .gestureZoomIn]))
    }
    #endif
}
