#if canImport(MapLibre)
import SwiftUI
import MapLibre

/// Путь Б итерации 4: MapLibre Native читает тот же style JSON, что бета.
struct MapLibreCanvas: UIViewRepresentable {
    let center: MapCanvasCenter
    let zoom: Double
    let style: URL?
    /// Под поворотом живого компаса пиксели жеста врут — тянуть нельзя,
    /// щипок остаётся (`dragPan.disable` веба).
    let panEnabled: Bool
    let focusShift: CGFloat
    let onMove: (MapCanvasCenter) -> Void
    let onCamera: (MapCanvasCamera) -> Void
    let onTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onMove: onMove, onCamera: onCamera, onTap: onTap) }

    func makeUIView(context: Context) -> MLNMapView {
        let view = MLNMapView(frame: .zero, styleURL: style)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.allowsRotating = false
        view.allowsTilting = false
        view.compassView.isHidden = true
        view.logoView.isHidden = true
        // Атрибуция стоит своей плашкой на кадре, как у веба (`.map-credit`).
        view.attributionButton.isHidden = true
        view.automaticallyAdjustsContentInset = false
        view.delegate = context.coordinator
        // Тап — свой распознаватель, уступающий двойному тапу движка
        // (приближение): одиночный срабатывает, только если второго не было.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        for case let other as UITapGestureRecognizer in view.gestureRecognizers ?? [] where other.numberOfTapsRequired == 2 {
            tap.require(toFail: other)
        }
        view.addGestureRecognizer(tap)
        context.coordinator.style = style
        apply(view, context: context, force: true)
        return view
    }

    func updateUIView(_ view: MLNMapView, context: Context) {
        context.coordinator.onMove = onMove
        context.coordinator.onCamera = onCamera
        context.coordinator.onTap = onTap
        if context.coordinator.style != style {
            context.coordinator.style = style
            view.styleURL = style
        }
        apply(view, context: context, force: false)
    }

    private func apply(_ view: MLNMapView, context: Context, force: Bool) {
        let c = context.coordinator
        if view.isScrollEnabled != panEnabled { view.isScrollEnabled = panEnabled }
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
        var onCamera: (MapCanvasCamera) -> Void
        var onTap: (CGPoint) -> Void
        var center: MapCanvasCenter?
        var inset: UIEdgeInsets = .zero
        var style: URL?

        init(onMove: @escaping (MapCanvasCenter) -> Void, onCamera: @escaping (MapCanvasCamera) -> Void,
             onTap: @escaping (CGPoint) -> Void) {
            self.onMove = onMove
            self.onCamera = onCamera
            self.onTap = onTap
        }

        private static let byHand: MLNCameraChangeReason = [.gesturePan, .gesturePinch, .gestureZoomIn,
                                                            .gestureZoomOut, .gestureOneFingerZoom]

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let v = g.view else { return }
            onTap(g.location(in: v))
        }

        /// Камера на каждом кадре — и пальца, и программы: булавки едут за
        /// картой, а не догоняют её в конце жеста.
        private func report(_ mapView: MLNMapView, _ reason: MLNCameraChangeReason) {
            let c = mapView.centerCoordinate
            // Переезд программой — не жест, даже если в маске осталась
            // причина прошлой протяжки (`originalEvent` веба у `jumpTo` нет).
            let hand = !reason.intersection(Self.byHand).isEmpty && !reason.contains(.programmatic)
            onCamera(MapCanvasCamera(center: MapCanvasCenter(latitude: c.latitude, longitude: c.longitude),
                                     zoom: mapView.zoomLevel, byHand: hand))
        }

        func mapView(_ mapView: MLNMapView, regionIsChangingWith reason: MLNCameraChangeReason) {
            report(mapView, reason)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            report(mapView, reason)
            guard !reason.intersection(Self.byHand).isEmpty else { return }
            let c = mapView.centerCoordinate
            let moved = MapCanvasCenter(latitude: c.latitude, longitude: c.longitude)
            center = moved
            onMove(moved)
        }
    }
}
#endif
