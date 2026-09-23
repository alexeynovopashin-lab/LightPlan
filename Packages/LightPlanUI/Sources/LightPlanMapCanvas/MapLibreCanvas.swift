#if canImport(MapLibre)
import SwiftUI
import MapLibre

/// Путь Б итерации 4: MapLibre Native читает тот же style JSON, что бета.
struct MapLibreCanvas: UIViewRepresentable {
    let center: MapCanvasCenter
    let zoom: Double
    let dark: Bool
    let focusShift: CGFloat
    let onMove: (MapCanvasCenter) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onMove: onMove) }

    func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero, styleURL: MapStyle.url(dark: dark))
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.allowsRotating = false
        view.allowsTilting = false
        view.compassView.isHidden = true
        view.logoView.isHidden = true
        // Атрибуция стоит своей плашкой на кадре, как у веба (`.map-credit`).
        view.attributionButton.isHidden = true
        view.automaticallyAdjustsContentInset = false
        view.delegate = context.coordinator
        context.coordinator.style = MapStyle.url(dark: dark)
        apply(view, context: context, force: true)
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        context.coordinator.onMove = onMove
        let style = MapStyle.url(dark: dark)
        if context.coordinator.style != style {
            context.coordinator.style = style
            view.styleURL = style
        }
        apply(view, context: context, force: false)
    }

    private func apply(_ view: MLNMapView, context: Context, force: Bool) {
        let c = context.coordinator
        let inset = UIEdgeInsets(top: max(0, -focusShift), left: 0, bottom: max(0, focusShift), right: 0)
        if force || c.inset != inset {
            c.inset = inset
            view.setContentInset(inset, animated: false, completionHandler: nil)
        }
        // Центр ставится, только когда его сменили снаружи: своё же движение
        // пальцем, вернувшееся через `onMove`, камеру назад не дёргает.
        if force || c.center != center {
            c.center = center
            view.setCenter(CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                           zoomLevel: zoom, animated: false)
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onMove: (MapCanvasCenter) -> Void
        var center: MapCanvasCenter?
        var inset: UIEdgeInsets = .zero
        var style: URL?

        init(onMove: @escaping (MapCanvasCenter) -> Void) { self.onMove = onMove }

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let byHand: MLNCameraChangeReason = [.gesturePan, .gesturePinch, .gestureZoomIn, .gestureZoomOut,
                                                 .gestureOneFingerZoom]
            guard !reason.intersection(byHand).isEmpty else { return }
            let c = mapView.centerCoordinate
            let moved = MapCanvasCenter(latitude: c.latitude, longitude: c.longitude)
            center = moved
            onMove(moved)
        }
    }
}
#endif
