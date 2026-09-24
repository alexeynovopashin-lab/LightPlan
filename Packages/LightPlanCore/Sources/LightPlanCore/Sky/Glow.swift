import Foundation

/// Засветка неба по атласу Дэвида Лоренца (порт `glowIndex`, `glowRead`,
/// `glowLevel`, `glowMag` веба; DECISIONS, «Засветка неба…»).
///
/// Число — `ratio`: во сколько раз искусственное свечение зенита превышает
/// естественный фон ночного неба. Ноль — небо до электричества, единица — своё
/// зарево сравнялось с природным. Это модель яркости в зените, а не шкала
/// Бортля — автор атласа просит их не путать.
///
/// Здесь только арифметика: где лежит точка и как прочесть её из распакованной
/// плитки. Загрузка и gzip — `GlowAtlas` в `LightPlanData`.
public enum Glow {
    /// Год атласа — часть адреса плитки.
    public static let year = 2025
    /// Плитка 5°×5° по сетке 1/120°: 600×600 однобайтовых приращений.
    public static let row = 600
    public static let size = row * row

    /// Где точка в атласе: номер плитки и ячейка внутри неё.
    public struct Index: Sendable, Equatable {
        public let tx: Int
        public let ty: Int
        public let ix: Int
        public let iy: Int
        /// Ключ плитки `tx_ty` — как в адресе и в кэше веба.
        public var tile: String { "\(tx)_\(ty)" }
    }

    /// `nil` — вне атласа: он кончается на 75° северной и 65° южной широты.
    /// Дальше не «ноль засветки», а «не знаем».
    public static func index(latitude lat: Double, longitude lon: Double) -> Index? {
        // Остаток двойным способом, как у веба и у оригинала атласа: последние
        // биты решают, какая ячейка ближе (DECISIONS: три замера из девяти).
        let lonD = ((lon + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let latS = lat + 65
        let tx = Int((lonD / 5).rounded(.down)) + 1
        let ty = Int((latS / 5).rounded(.down)) + 1
        guard ty >= 1, ty <= 28 else { return nil }
        return Index(tx: tx, ty: ty,
                     ix: jsRound(120 * (lonD - 5 * Double(tx - 1) + 1.0 / 240)),
                     iy: jsRound(120 * (latS - 5 * Double(ty - 1) + 1.0 / 240)))
    }

    /// Значение в ячейке: первая точка двумя байтами, дальше ход по столбцу и
    /// затем по строке. Байты знаковые — прочитанные без знака, приращения вниз
    /// сделали бы тёмное место ярче города. Плитка короче сетки — `nil`.
    public static func read(_ raw: [UInt8], ix: Int, iy: Int) -> Double? {
        guard raw.count >= size else { return nil }
        var v = 128 * s8(raw[0]) + s8(raw[1])
        if iy > 1 { for i in 1..<iy { v += s8(raw[row * i + 1]) } }
        if ix > 1 { for i in 1..<ix { v += s8(raw[row * (iy - 1) + 1 + i]) } }
        // Обратная развёртка сжатия автора. У дна шкалы выходит чуть меньше
        // нуля — шум оцифровки, а не «темнее нетронутого неба».
        return max(0, (5.0 / 195) * (exp(0.0195 * Double(v)) - 1))
    }

    /// Ступени для камеры, не для глаза: до 1 Путь через весь купол, до 8 —
    /// уверенно, но край тонет у горизонта, до 27 — только ядро, дальше пусто.
    public enum Level: String, Sendable, CaseIterable {
        case dark, faint, city, none
    }

    public static func level(_ r: Double?) -> Level? {
        guard let r else { return nil }
        return r < 1 ? .dark : r < 8 ? .faint : r < 27 ? .city : Level.none
    }

    /// Яркость неба в mag/arcsec²: 22.0 — нетронутое небо, пять величин —
    /// стократная разница.
    public static func magnitude(_ r: Double) -> Double {
        22 - 5 * log(1 + r) / log(100)
    }

    private static func s8(_ b: UInt8) -> Int { Int(Int8(bitPattern: b)) }

    /// `Math.round` веба: половина — вверх, и для отрицательных тоже.
    private static func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }
}
