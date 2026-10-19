import SwiftUI
import LightPlanCore

/// Числа для шейдера `milkyWaySky` (`MilkyWaySky.metal`): лучи окна, оси галактики, видимость. Раскладка — в
/// заголовке шейдера.
enum MilkyWaySkyShader {
    private static let library = ShaderLibrary.bundle(.module)

    /// Части картины: гладкая (меряется по кадру), текстура (облака и зерно звёзд), пыль.
    struct Parts: OptionSet, Sendable {
        let rawValue: Int
        static let smooth = Parts(rawValue: 1)
        static let texture = Parts(rawValue: 2)
        static let dust = Parts(rawValue: 4)
        static let all: Parts = [.smooth, .texture, .dust]

        /// В выпуске — все; в отладке `-LPSunARMWParts smooth,texture,dust` выбирает (замер профиля — только гладкая).
        static var current: Parts {
            #if DEBUG
            if let list = UserDefaults.standard.string(forKey: "LPSunARMWParts") {
                var p: Parts = []
                for w in list.split(separator: ",") {
                    switch w.trimmingCharacters(in: .whitespaces) {
                    case "smooth": p.insert(.smooth)
                    case "texture": p.insert(.texture)
                    case "dust": p.insert(.dust)
                    default: break
                    }
                }
                return p
            }
            #endif
            return .all
        }
    }

    /// Подпись «ядро». В отладке `-LPSunARMWParts` без слова `label` её прячет: замер ядра по кадру смотрит на свет,
    /// а плашка лежит в тридцати точках под ним.
    static var labelShown: Bool {
        #if DEBUG
        if let list = UserDefaults.standard.string(forKey: "LPSunARMWParts") { return list.contains("label") }
        #endif
        return true
    }

    /// Ширина профиля σ из ядра (`MilkyWayLook.sigma`, края — `MilkyWay.halfWidth`) шагом 3° по долготе, 121 число
    /// (последнее — снова l = 0): шейдер берёт её отсюда и между узлами ведёт прямой, своей формулы ширины у него нет.
    /// Между узлами ошибка не больше 0,002° (вторая производная σ меньше 0,0012 на квадратный градус).
    static let sigmaStep: Degrees = 3
    static let sigmaTable: [Float] = (0...120).map { Float(MilkyWayLook.sigma(Double($0) * sigmaStep)) }

    static func numbers(_ pic: NightSkyARScene.MilkyWayPicture, origin: CGPoint, parts: Parts) -> [Float] {
        let f = pic.frame
        let axes = [f.x, f.y, f.z].flatMap { [$0.east, $0.north, $0.up] }
        return (pic.pixelToSky + axes + [Double(origin.x), Double(origin.y), pic.visibility.factor, Double(parts.rawValue),
                                         MilkyWayLook.peakAlpha, pic.focal]).map { Float($0) } + sigmaTable
    }

    static func shader(_ pic: NightSkyARScene.MilkyWayPicture, origin: CGPoint, parts: Parts) -> Shader {
        library.milkyWaySky(.floatArray(numbers(pic, origin: origin, parts: parts)))
    }
}
