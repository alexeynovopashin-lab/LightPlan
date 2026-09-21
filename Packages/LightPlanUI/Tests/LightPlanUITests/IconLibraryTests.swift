import Foundation
import SwiftUI
import Testing
@testable import LightPlanUI

/// Состав и устройство библиотеки знаков. Цифры — из замера `beta/icons.js`
/// 21 сентября 2026; правится знак в вебе — цифры здесь двигает `make icons`
/// и глаз, а не тихая подгонка.
@MainActor
struct IconLibraryTests {

    /// Знаков в общем словаре после слияния (первый набор побеждает), жанров, пожеланий.
    @Test func libraryCounts() {
        #expect(IconLibrary.common.count == 196)
        #expect(IconLibrary.genres.count == 12)
        #expect(IconLibrary.wishes.count == 8)
        #expect(IconLibrary.sheet.map(\.names.count) == [3, 78, 31, 10, 59, 15, 12, 8, 1])
    }

    /// Каждое имя из каждого набора разбирается в непустой знак.
    @Test func everyBodyDecodes() {
        for (ns, table) in [("common", IconLibrary.common), ("genres", IconLibrary.genres), ("wishes", IconLibrary.wishes)] {
            for (name, text) in table {
                let art = IconArt.decode(text)
                #expect(!art.parts.isEmpty, "\(ns):\(name) без частей")
                for part in art.parts {
                    #expect(!part.path.isEmpty, "\(ns):\(name): пустая часть")
                    let box = part.path.boundingRect
                    // Холст 24×24; допуск на выступ за край — у знаков вроде дуги он бывает.
                    #expect(box.minX > -1 && box.minY > -1 && box.maxX < 25 && box.maxY < 25, "\(ns):\(name) вне холста: \(box)")
                }
            }
        }
    }

    /// «Одна толщина линии на весь набор»: своя толщина есть у единственной части —
    /// клеток флага финиша, — и у неё плоские концы.
    @Test func oneLineWidthAcrossTheSet() {
        var own: [String] = []
        var butt: [String] = []
        for (ns, table) in [("common", IconLibrary.common), ("genres", IconLibrary.genres), ("wishes", IconLibrary.wishes)] {
            for (name, text) in table {
                for part in IconArt.decode(text).parts {
                    if part.width != nil { own.append("\(ns):\(name)=\(part.width!)") }
                    if part.butt { butt.append("\(ns):\(name)") }
                }
            }
        }
        #expect(own == ["common:flag_finish=4.4"])
        #expect(butt == ["common:flag_finish"])
    }

    /// Погода красится по частям: облако, осадки и солнце — отдельные роли.
    @Test func weatherPartsAreNamed() {
        func roles(_ n: String) -> [IconArt.Role] { IconArt.decode(IconLibrary.common[n]!).parts.map(\.role) }
        #expect(roles("part") == [.sun, .cloud])
        #expect(roles("rain") == [.cloud, .rain])
        #expect(roles("snow") == [.cloud, .rain])
        #expect(roles("fog") == [.cloud])
        #expect(roles("clear") == [.sun])
    }

    /// Неизвестное имя — нейтральный кружок, а не пустота: разметка не ломается.
    @Test func unknownNameFallsBackToDot() {
        let dot = IconArt.decode(IconLibrary.common["dot"]!)
        let fallback = Icon.common("no_such_sign")
        #expect(fallback.parts.count == dot.parts.count)
        #expect(fallback.parts.first?.path.boundingRect == dot.parts.first?.path.boundingRect)
        #expect(IconLibrary.genres["landscape"] != nil && IconLibrary.common["camera"] != nil)
    }

    /// Имена жанров и пожеланий живут в своих пространствах: `rain` пожелания — не `rain` погоды.
    @Test func namespacesAreSeparate() {
        #expect(IconLibrary.wishes["rain"] != IconLibrary.common["rain"])
        #expect(IconLibrary.genres["street"] != IconLibrary.common["street"])
    }

    /// Разбор пути на знакомой фигуре: квадрат со сторонами 2 и 4.
    @Test func pathDecoder() {
        let p = IconArt.path(from: "M1 1L3 1L3 5L1 5Z")
        #expect(p.boundingRect == CGRect(x: 1, y: 1, width: 2, height: 4))
        let q = IconArt.path(from: "M0 0C0 10 10 10 10 0Q5 -5 0 0Z")
        #expect(q.boundingRect.width == 10)
    }
}
