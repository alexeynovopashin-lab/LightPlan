import Foundation
import ImageIO
import simd

/// Данные Gaia DR3 для слоя «Млечный Путь» (шаг 29.8в.19): звёзды G ≤ 10 точками и свечение слабых звёзд картой.
/// Слово Алексея 20.10: «россыпь звезд и систем с реальными координатами… Млечный путь — это не рисунок, это
/// галактика». Файлы — `MilkyWayData/` (копия `Tools/milkyway_gaia/`, `make mwdata`), формат — `spec.json`.
///
/// **Лицензия некоммерческая:** CC BY-NC 3.0 IGO, «Credit: ESA, Gaia DPAC», данные изменены (выборка и суммы по
/// ячейкам). До монетизации нужно письмо в ESA (data.licences@esa.int) — `MilkyWayData/README.md`. Нет файлов или
/// они испорчены — `shared` пуст, и слой рисует прежнюю гладкую полосу шейдера (`MilkyWaySky.metal`).
///
/// Читается один раз за запуск (`shared`), дальше живёт неизменным: вход и выход из AR его не перечитывают.
final class MilkyWayGaia: @unchecked Sendable {
    /// Звёзды ярче этой G рисует слой «Звёзды» из каталога приложения: Gaia у них неполна (насыщение детектора),
    /// и одну звезду не рисуем дважды.
    static let brightestG: Double = 3.5
    /// Не больше стольких звёзд на кадре (бюджет шага).
    static let budget = 80_000

    /// Записи файла как есть: 8 байт на звезду (`ushort l; short b; uchar g; char bp_rp; uchar flags; uchar pad`).
    let records: Data
    let count: Int
    /// Первая запись с G ≥ `brightestG`: файл идёт от ярких к слабым.
    let start: Int
    /// `prefix[g]` — сколько записей с G·10 ≤ g (g = 0…255): «звёзды до G» — первые `prefix[g]` записей.
    let prefix: [Int]
    /// Карта свечения: RGBA, 16 бит без знака, альфа 65535; строка 0 — b = +90°, столбец 0 — l = 180°.
    let glow: [UInt16]
    let glowWidth: Int
    let glowHeight: Int
    /// Цвет точки по сырому BP−RP (индекс raw + 128): самый яркий канал = 1, белая точка — чёрное тело 5800 K.
    let colors: [SIMD4<Float>]
    /// Число звёзд по ячейкам 5° × 5° и G: `cells[(ib·72 + il)·256 + g]` — сколько звёзд ячейки с G·10 ≤ g
    /// (от `start`). Для бюджета: сколько звёзд попадёт в кадр при пределе G — сумма по ячейкам в кадре.
    let cells: [Int32]
    static let cellDeg = 5.0
    static let cellsL = 72, cellsB = 36

    /// Сколько раз данные читались с диска за запуск (замер памяти: должен быть один раз).
    nonisolated(unsafe) private(set) static var loads = 0

    /// Данные приложения. `nil` — файлов нет или они испорчены: слой рисует запасной вариант.
    static let shared: MilkyWayGaia? = {
        guard let dir = Bundle.module.url(forResource: "MilkyWayData", withExtension: nil) else { return nil }
        return load(directory: dir)
    }()

    /// Файлы лежат в приложении — без чтения (для кредита в «О приложении»).
    static var bundled: Bool { Bundle.module.url(forResource: "MilkyWayData/stars_gaia", withExtension: "bin") != nil }

    static func load(directory: URL) -> MilkyWayGaia? {
        loads += 1
        guard let stars = try? Data(contentsOf: directory.appendingPathComponent("stars_gaia.bin"), options: .mappedIfSafe),
              let specData = try? Data(contentsOf: directory.appendingPathComponent("spec.json")),
              let spec = try? JSONSerialization.jsonObject(with: specData) as? [String: Any],
              let table = bvTable(spec),
              let glow = readGlow(directory.appendingPathComponent("milkyway_glow_gaia.png")) else { return nil }
        return MilkyWayGaia(stars: stars, table: table, glow: glow)
    }

    private init?(stars: Data, table: (bprp: [Double], bv: [Double]), glow: (pixels: [UInt16], w: Int, h: Int)) {
        guard stars.count >= 16, stars.prefix(4) == Data("LPGS".utf8) else { return nil }
        func u16(_ o: Int) -> Int { Int(stars[stars.startIndex + o]) | Int(stars[stars.startIndex + o + 1]) << 8 }
        let n = u16(8) | u16(10) << 16
        guard u16(4) == 1, u16(6) == 8, stars.count == 16 + 8 * n else { return nil }
        records = stars.subdata(in: (stars.startIndex + 16)..<stars.endIndex)
        count = n
        var prefix = [Int](repeating: 0, count: 256)
        var cells = [Int32](repeating: 0, count: Self.cellsL * Self.cellsB * 256)
        var first = n
        let limit = Int((Self.brightestG * 10).rounded())
        records.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<n {
                let o = 8 * i
                let g = Int(raw[o + 4])
                prefix[g] += 1
                guard g >= limit else { continue }
                if first == n { first = i }
                let l = Double(UInt16(raw[o]) | UInt16(raw[o + 1]) << 8) * 360 / 65536
                let b = Double(Int16(bitPattern: UInt16(raw[o + 2]) | UInt16(raw[o + 3]) << 8)) * 180 / 65536
                let il = min(Self.cellsL - 1, Int(l / Self.cellDeg))
                let ib = min(Self.cellsB - 1, max(0, Int((b + 90) / Self.cellDeg)))
                cells[(ib * Self.cellsL + il) * 256 + g] += 1
            }
        }
        for g in 1..<256 { prefix[g] += prefix[g - 1] }
        for c in 0..<(Self.cellsL * Self.cellsB) {
            for g in 1..<256 { cells[c * 256 + g] += cells[c * 256 + g - 1] }
        }
        start = first
        self.prefix = prefix
        self.cells = cells
        self.glow = glow.pixels
        glowWidth = glow.w
        glowHeight = glow.h
        colors = (0..<256).map { i in Self.starColor(bprp: Double(i - 128) / 10, table: table) }
    }

    /// Запись звезды: галактические l, b (градусы), G и сырой BP−RP.
    func star(_ i: Int) -> (l: Double, b: Double, g: Double, bprp: Int8) {
        records.withUnsafeBytes { raw in
            let o = 8 * i
            let l = Double(UInt16(raw[o]) | UInt16(raw[o + 1]) << 8) * 360 / 65536
            let b = Double(Int16(bitPattern: UInt16(raw[o + 2]) | UInt16(raw[o + 3]) << 8)) * 180 / 65536
            return (l, b, Double(raw[o + 4]) / 10, Int8(bitPattern: raw[o + 5]))
        }
    }

    // MARK: - Карта свечения

    /// PNG 16 бит RGB без гаммы (`spec.json → glow`): пиксели читаются как есть, без пересчёта цвета — значения
    /// линейные, их тонирует шейдер. Порядок байт — по `bitmapInfo` (у PNG обычно старший байт первым).
    private static func readGlow(_ url: URL) -> (pixels: [UInt16], w: Int, h: Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              img.bitsPerComponent == 16, img.bitsPerPixel == 48 || img.bitsPerPixel == 64,
              let data = img.dataProvider?.data as Data? else { return nil }
        let w = img.width, h = img.height, row = img.bytesPerRow, step = img.bitsPerPixel / 16
        guard w > 0, h > 0, data.count >= row * h else { return nil }
        let little = img.bitmapInfo.contains(.byteOrder16Little)
        var out = [UInt16](repeating: 65535, count: w * h * 4)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for y in 0..<h {
                for x in 0..<w {
                    for c in 0..<3 {
                        let o = y * row + (x * step + c) * 2
                        let a = UInt16(raw[o]), b = UInt16(raw[o + 1])
                        out[(y * w + x) * 4 + c] = little ? (a | b << 8) : (a << 8 | b)
                    }
                }
            }
        }
        return (out, w, h)
    }

    // MARK: - Цвет звезды: BP−RP → B−V → температура → линейный sRGB (то же правило, что у карты, `color.py`)

    private static func bvTable(_ spec: [String: Any]) -> (bprp: [Double], bv: [Double])? {
        guard let glow = spec["glow"] as? [String: Any], let color = glow["color"] as? [String: Any],
              let t = color["bp_rp_to_b_v"] as? [String: Any],
              let x = t["bp_rp"] as? [Double], let y = t["b_v"] as? [Double], x.count == y.count, x.count > 1 else { return nil }
        return (x, y)
    }

    private static func interp(_ v: Double, _ xs: [Double], _ ys: [Double]) -> Double {
        if v <= xs[0] { return ys[0] }
        if v >= xs[xs.count - 1] { return ys[ys.count - 1] }
        var i = 1
        while xs[i] < v { i += 1 }
        let t = (v - xs[i - 1]) / (xs[i] - xs[i - 1])
        return ys[i - 1] + t * (ys[i] - ys[i - 1])
    }

    /// Ballesteros 2012: T = 4600 K·(1/(0,92(B−V) + 1,7) + 1/(0,92(B−V) + 0,62)), 2000…40000 K.
    static func temperature(bv: Double) -> Double {
        let c = min(max(bv, -0.4), 2.0)
        return min(max(4600 * (1 / (0.92 * c + 1.7) + 1 / (0.92 * c + 0.62)), 2000), 40000)
    }

    /// Линейный sRGB чёрного тела (с точностью до множителя): Планк × кривые CIE 1931 (Wyman, Sloan, Shirley 2013).
    static func blackbody(_ T: Double) -> SIMD3<Double> {
        func g(_ l: Double, _ mu: Double, _ s1: Double, _ s2: Double) -> Double {
            let s = l < mu ? s1 : s2
            return exp(-0.5 * ((l - mu) / s) * ((l - mu) / s))
        }
        var xyz = SIMD3<Double>(0, 0, 0)
        var lam = 360.0
        while lam <= 830 {
            let x = 1.056 * g(lam, 599.8, 37.9, 31.0) + 0.362 * g(lam, 442.0, 16.0, 26.7) - 0.065 * g(lam, 501.1, 20.4, 26.2)
            let y = 0.821 * g(lam, 568.8, 46.9, 40.5) + 0.286 * g(lam, 530.9, 16.3, 31.1)
            let z = 1.217 * g(lam, 437.0, 11.8, 36.0) + 0.681 * g(lam, 459.0, 26.0, 13.8)
            let m = lam * 1e-9
            let p = 1 / (pow(m, 5) * expm1(1.4387769e-2 / (m * T)))
            xyz += p * SIMD3(x, y, z)
            lam += 1
        }
        return SIMD3(3.2406 * xyz.x - 1.5372 * xyz.y - 0.4986 * xyz.z,
                     -0.9689 * xyz.x + 1.8758 * xyz.y + 0.0415 * xyz.z,
                     0.0557 * xyz.x - 0.2040 * xyz.y + 1.0570 * xyz.z)
    }

    private static let white = blackbody(5800)

    static func starColor(bprp: Double, table: (bprp: [Double], bv: [Double])) -> SIMD4<Float> {
        let rgb = simd_max(blackbody(temperature(bv: interp(bprp, table.bprp, table.bv))) / white, SIMD3(repeating: 0))
        let m = max(rgb.x, rgb.y, rgb.z, 1e-9)
        return SIMD4(Float(rgb.x / m), Float(rgb.y / m), Float(rgb.z / m), 1)
    }
}
