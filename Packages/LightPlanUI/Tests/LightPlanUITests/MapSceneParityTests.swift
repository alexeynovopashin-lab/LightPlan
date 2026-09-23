import CoreGraphics
import Foundation
import SwiftUI
import Testing
import LightPlanCore
@testable import LightPlanUI

/// Снимок сцены прибора карты (итерация 20а) против разметки живой беты.
///
/// Эталон `map_scene_ref.json` снимает `Tools/map_ref.js`: `renderMap` веба в
/// Chromium на входах пар снимков — Барнаул, 23 сентября 2026, день, золотой
/// час, ночь, рассвет; «Просто» и «Астро»; обе темы. Сцена строится на тех же
/// входах и сверяется элемент за элементом: порядок, вид, координаты,
/// толщина, пунктир, цвет, подписи. Пара снимков сверяет рамки на экране —
/// здесь то, что под ними: каждая точка облака и каждый отрезок пути.
struct MapSceneParityTests {

    // MARK: - Эталон

    struct Ref: Decodable {
        struct PlaceRef: Decodable { let lat: Double; let lon: Double; let zone: String }
        struct Case: Decodable {
            let name: String
            let date: String
            let minute: Double
            let pro: Bool
            let light: Bool
            let layers: [String: Bool]
            let elements: [El]
        }
        /// Узел разметки в числах (`k` — вид). Необязательные поля — у кого есть.
        struct El: Decodable {
            let k: String
            var x: Double?, y: Double?, r: Double?
            var x1: Double?, y1: Double?, x2: Double?, y2: Double?
            var fill: [Double]?, stroke: [Double]?, color: [Double]?
            var w: Double?, dash: [Double]?, round: Bool?
            var runs: [[[Double]]]?, pts: [[Double]]?
            var text: String?, size: Double?, weight: Double?, mono: Bool?, anchor: String?
            var tracking: Double?, middle: Bool?
        }
        let place: PlaceRef
        let cases: [Case]
    }

    private static func load() throws -> Ref {
        var u = URL(fileURLWithPath: #filePath)
        u.deleteLastPathComponent()
        u.appendPathComponent("map_scene_ref.json")
        return try JSONDecoder().decode(Ref.self, from: Data(contentsOf: u))
    }

    static func input(_ ref: Ref, _ c: Ref.Case) -> (MapInstrument.Input, MapInstrument.Day) {
        let ymd = c.date.split(separator: "-").compactMap { Int($0) }
        let date = CivilDate(year: ymd[0], month: ymd[1], day: ymd[2])
        let place = Place(latitude: ref.place.lat, longitude: ref.place.lon, zone: ZoneID(ref.place.zone)!)
        let solar = SolarDay(date: date, place: place)
        let clock = ClockText(language: "ru", preference: .h24)
        let input = MapInstrument.Input(
            date: date, minute: c.minute, solar: solar, place: place, layers: MapLayers(c.layers), pro: c.pro,
            lightTheme: c.light, chip: nil, clock: { clock.fmt($0) }, cardinals: ["С", "В", "Ю", "З"])
        return (input, MapInstrument.Day(date: date, place: place, solar: solar))
    }

    // MARK: - Сверка

    /// Координаты веба — double без округления (у путей и облака — один знак,
    /// так же округляет и сцена); эталон хранит четыре знака.
    static let eps = 0.01

    @Test func sceneMatchesWebMarkupElementByElement() throws {
        let ref = try Self.load()
        #expect(ref.cases.count == 16)
        for c in ref.cases {
            let (input, day) = Self.input(ref, c)
            let scene = MapInstrument.scene(input, day: day)
            let web = c.elements.filter { $0.k != "hit" }
            var diffs: [String] = []
            if web.count != scene.elements.count {
                diffs.append("элементов: веб \(web.count), натив \(scene.elements.count)")
            }
            for (i, pair) in zip(web, scene.elements).enumerated() {
                if let d = Self.diff(pair.0, pair.1) { diffs.append("#\(i) \(pair.0.k): \(d)") }
                if diffs.count >= 6 { break }
            }
            // Мишени тапа веба стоят на светилах — у натива там кнопки.
            for hit in c.elements where hit.k == "hit" {
                let p = CGPoint(x: hit.x!, y: hit.y!)
                let on = [scene.sunAt, scene.moonAt].contains { $0.map { Self.near($0, p) } ?? false }
                if !on { diffs.append("мишень тапа \(p) не на светиле") }
            }
            #expect(diffs.isEmpty, "\(c.name): \(diffs.joined(separator: "; "))")
        }
    }

    private static func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < eps && abs(a.y - b.y) < eps }
    private static func near(_ a: Double, _ b: Double?) -> Bool { b.map { abs(a - $0) < eps } ?? false }

    /// Цвет: каналы до половины единицы, прозрачность до 0,002 (веб пишет
    /// `toFixed(2…3)`, а `*-opacity` умножен в эталоне).
    private static func same(_ c: RGBA?, _ w: [Double]?) -> Bool {
        switch (c, w) {
        case (nil, nil): return true
        case (let c?, let w?):
            return abs(c.r - w[0]) < 0.5 && abs(c.g - w[1]) < 0.5 && abs(c.b - w[2]) < 0.5 && abs(c.a - w[3]) < 0.002
        default: return false
        }
    }

    private static func dash(_ d: [CGFloat], _ w: [Double]?) -> Bool { d.map(Double.init) == (w ?? []) }

    private static func point(_ p: CGPoint, _ w: [Double]) -> Bool { near(p, CGPoint(x: w[0], y: w[1])) }

    private static func diff(_ w: Ref.El, _ n: MapInstrument.Element) -> String? {
        switch n {
        case .scrim(let c, let r):
            guard w.k == "scrim" else { return "натив — обод" }
            return near(c.x, w.x) && near(c.y, w.y) && near(r, w.r) ? nil : "обод \(c) r \(r)"
        case .circle(let c, let r, let fill, let stroke, let width, let d):
            guard w.k == "circle" else { return "натив — круг \(c)" }
            if !(near(c.x, w.x) && near(c.y, w.y) && near(r, w.r)) {
                return "круг \(c) r \(r) против \(w.x!),\(w.y!) r \(w.r!)"
            }
            if !same(fill, w.fill) || !same(stroke, w.stroke) { return "цвет круга \(c) r \(r)" }
            if (stroke != nil && !near(width, w.w)) || !dash(d, w.dash) { return "линия круга r \(r)" }
            return nil
        case .line(let a, let b, let stroke, let width, let d, let round):
            guard w.k == "line" else { return "натив — отрезок \(a)" }
            if !(near(a.x, w.x1) && near(a.y, w.y1) && near(b.x, w.x2) && near(b.y, w.y2)) {
                return "отрезок \(a)–\(b) против \(w.x1!),\(w.y1!)–\(w.x2!),\(w.y2!)"
            }
            if !same(stroke, w.stroke) || !near(width, w.w) || !dash(d, w.dash) || round != (w.round ?? false) {
                return "вид отрезка \(a)"
            }
            return nil
        case .path(let runs, let stroke, let width, let d):
            guard w.k == "path", let wr = w.runs else { return "натив — путь" }
            if runs.count != wr.count || zip(runs, wr).contains(where: { $0.count != $1.count }) {
                return "прогонов \(runs.map(\.count)) против \(wr.map(\.count))"
            }
            for (r, q) in zip(runs, wr) {
                for (p, v) in zip(r, q) where !point(p, v) { return "точка пути \(p) против \(v)" }
            }
            if !same(stroke, w.stroke) || !near(width, w.w) || !dash(d, w.dash) { return "вид пути" }
            return nil
        case .dots(let pts, let color, let width):
            guard w.k == "dots", let wp = w.pts else { return "натив — облако" }
            if pts.count != wp.count { return "точек облака \(pts.count) против \(wp.count)" }
            for (p, v) in zip(pts, wp) where !point(p, v) { return "точка облака \(p) против \(v)" }
            return same(color, w.color) && near(width, w.w) ? nil : "вид облака"
        case .text(let s, let center, let size, let weight, let mono, let color, let anchor, let tracking):
            guard w.k == "text" else { return "натив — подпись «\(s)»" }
            if s != w.text { return "«\(s)» против «\(w.text ?? "")»" }
            // Середина строки у натива; у веба — базовая линия, кроме
            // `dominant-baseline: middle` (числа азимута).
            let y = (w.middle ?? false) ? center.y : center.y + size * MapInstrument.textMid
            if !(near(center.x, w.x) && near(y, w.y)) { return "«\(s)» в \(center.x),\(y) против \(w.x!),\(w.y!)" }
            let wt: Double = weight == .bold ? 700 : weight == .semibold ? 600 : 400
            let an = anchor == .start ? "start" : anchor == .end ? "end" : "middle"
            if !near(size, w.size) || wt != w.weight || mono != w.mono || an != w.anchor || !near(tracking, w.tracking)
                || !same(color, w.color) {
                return "вид «\(s)»"
            }
            return nil
        case .chip:
            return "натив — чип (в покое его нет)"
        }
    }
}
