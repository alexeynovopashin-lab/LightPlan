import SwiftUI
import MapLibre

/// Путь Б: MapLibre Native читает тот же самый style JSON, что и бета в
/// браузере. Холст задан числами по слоям, а не фильтром и не темой окна.
/// Плитки в песочнице — бесплатные векторные CARTO (те же, что в вебе);
/// вопрос платного поставщика решается на бумаге, а не здесь.
struct MapLibreCanvas: UIViewRepresentable {
    let place: Place
    let dark: Bool

    func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero, styleURL: StyleStore.url(dark: dark))
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Поворот выключён, как в вебе: прибор и есть карта, крутиться они
        // должны одним куском (DECISIONS, «Карта на вектор»).
        view.allowsRotating = false
        view.allowsTilting = false
        view.compassView.isHidden = true
        view.logoView.isHidden = true
        // Атрибуция OSM/CARTO остаётся: это условие бесплатного доступа.
        view.attributionButton.isHidden = false
        view.setCenter(.init(latitude: place.lat, longitude: place.lon),
                       zoomLevel: place.zoom, animated: false)
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        if view.styleURL != StyleStore.url(dark: dark) {
            view.styleURL = StyleStore.url(dark: dark)
        }
        let c = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
        if abs(view.centerCoordinate.latitude - c.latitude) > 0.0005
            || abs(view.centerCoordinate.longitude - c.longitude) > 0.0005 {
            view.setCenter(c, zoomLevel: place.zoom, animated: false)
        }
    }
}
