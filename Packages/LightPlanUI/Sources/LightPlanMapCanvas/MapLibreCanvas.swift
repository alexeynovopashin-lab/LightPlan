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
        #if DEBUG
        ShotPinch.run(view, context.coordinator)
        #endif
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
        if force || Coordinator.mustPlace(center, given: c.given, camera: c.center) {
            c.center = center
            view.setCenter(CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                           zoomLevel: zoom, animated: false)
        }
        c.given = center
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onMove: (MapCanvasCenter) -> Void
        var onCamera: (MapCanvasCamera) -> Void
        var onTap: (CGPoint) -> Void
        /// Где камера по нашим сведениям: поставлена программой или оставлена пальцем.
        var center: MapCanvasCenter?
        /// Центр, который SwiftUI прислал в прошлый раз.
        var given: MapCanvasCenter?
        var inset: UIEdgeInsets = .zero
        var style: URL?

        init(onMove: @escaping (MapCanvasCenter) -> Void, onCamera: @escaping (MapCanvasCamera) -> Void,
             onTap: @escaping (CGPoint) -> Void) {
            self.onMove = onMove
            self.onCamera = onCamera
            self.onTap = onTap
        }

        /// Ставить ли камеру на присланный центр. Сменили снаружи — это
        /// когда присланный центр не тот, что в прошлый раз (`onChange` у
        /// MapKit), а не когда он не совпал с камерой: после щипка SwiftUI
        /// ещё кадр рисует прежнее место — оно доезжает до таймбара своей
        /// задачей, — и холст ставил старый центр с уровнем 14 (замер 21б:
        /// 16 → 14 через 12 мс). Своё же движение пальцем, вернувшееся через
        /// `onMove`, камеру назад не дёргает.
        static func mustPlace(_ center: MapCanvasCenter, given: MapCanvasCenter?,
                              camera: MapCanvasCenter?) -> Bool {
            center != given && center != camera
        }

        private static let handReasons: MLNCameraChangeReason = [.gesturePan, .gesturePinch, .gestureZoomIn,
                                                                 .gestureZoomOut, .gestureOneFingerZoom]

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let v = g.view else { return }
            onTap(g.location(in: v))
        }

        /// Камера на каждом кадре — и пальца, и программы: булавки едут за
        /// картой, а не догоняют её в конце жеста.
        private func report(_ mapView: MLNMapView, _ reason: MLNCameraChangeReason) {
            let c = mapView.centerCoordinate
            onCamera(MapCanvasCamera(center: MapCanvasCenter(latitude: c.latitude, longitude: c.longitude),
                                     zoom: mapView.zoomLevel, byHand: Self.byHand(reason)))
        }

        /// Переезд программой — не жест, даже если в маске осталась причина
        /// прошлой протяжки (`originalEvent` веба у `jumpTo` нет).
        static func byHand(_ reason: MLNCameraChangeReason) -> Bool {
            !reason.intersection(Self.handReasons).isEmpty && !reason.contains(.programmatic)
        }

        func mapView(_ mapView: MLNMapView, regionIsChangingWith reason: MLNCameraChangeReason) {
            report(mapView, reason)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            report(mapView, reason)
            guard !reason.intersection(Self.handReasons).isEmpty else { return }
            let c = mapView.centerCoordinate
            let moved = MapCanvasCenter(latitude: c.latitude, longitude: c.longitude)
            center = moved
            onMove(moved)
        }
    }
}

#if DEBUG
/// Прибор 21б (`make pinch`): щипок без пальцев. Симулятору руку не дать,
/// поэтому холсту говорится ровно то, что движок говорит в конце щипка:
/// камера уже на новом уровне, центр съехал к точке между пальцами,
/// причина — `.gesturePinch`. Дальше путь тот же, что у пальца: `onMove`,
/// переезд места, новый кадр SwiftUI. Ошибка — гонка кадра со старым местом
/// и доставки нового (на старом коде ловилась в 4 прогонах из 6), поэтому
/// щипков пять подряд; после каждого через 1 с пишется уровень холста и
/// остался ли центр там, куда его увели пальцы.
enum ShotPinch {
    static let levels: [Double] = [16, 15, 17, 15.5, 16.5]

    static func run(_ view: MLNMapView, _ coordinator: MapLibreCanvas.Coordinator) {
        guard let out = UserDefaults.standard.string(forKey: "LPShotPinchReport") else { return }
        Task { @MainActor [weak view] in
            try? await Task.sleep(for: .seconds(4))
            guard let view else { return }
            var seen: [String: Any] = ["before": view.zoomLevel]
            var zooms: [Double] = [], stayed: [Bool] = []
            for level in levels {
                // Пальцы правее и выше центра: щипок тянет центр к ним.
                let c = view.centerCoordinate
                let pinched = CLLocationCoordinate2D(latitude: c.latitude + 0.0005, longitude: c.longitude + 0.0008)
                view.setCenter(pinched, zoomLevel: level, animated: false)
                coordinator.mapView(view, regionDidChangeWith: .gesturePinch, animated: false)
                try? await Task.sleep(for: .seconds(1))
                let now = view.centerCoordinate
                zooms.append(view.zoomLevel)
                stayed.append(abs(now.latitude - pinched.latitude) + abs(now.longitude - pinched.longitude) < 1e-6)
            }
            seen["levels"] = levels
            seen["zooms"] = zooms
            seen["stayed"] = stayed
            let json = try? JSONSerialization.data(withJSONObject: seen, options: [.sortedKeys])
            try? json?.write(to: URL(fileURLWithPath: out))
        }
    }
}
#endif
#endif
