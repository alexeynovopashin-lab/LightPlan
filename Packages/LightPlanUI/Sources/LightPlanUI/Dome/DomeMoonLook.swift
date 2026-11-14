import SwiftUI

/// 28к.6 (эскиз `sketches_2026-11-14`, «луна», вариант М2; слова Алексея: «Луна чёрная и слишком маленькая, в светлой теме»).
/// Светлая тема: диск ночно-синий #34476B с белой кромкой, освещённая часть белая, диаметр 22 pt вместо 15. Тёмная — как была
/// (диск #16161A, кромка цвета страницы 2,5 pt, светлая часть #CFD6DE, радиус 7,5): ни одной точки не сдвинуто.
enum DomeMoonLook {
    static func discRadius(light: Bool) -> CGFloat { light ? 11 : 7.5 }
    static func disc(light: Bool) -> Color { light ? Color(red: 0x34 / 255, green: 0x47 / 255, blue: 0x6B / 255) : Color(red: 0x16 / 255, green: 0x16 / 255, blue: 0x1A / 255) }
    static func lit(light: Bool) -> Color { light ? .white : Color(red: 0xCF / 255, green: 0xD6 / 255, blue: 0xDE / 255) }
    /// Светлая тема: белая кромка 1,6 pt поверх диска и освещённой части; тёмная — кромка цвета страницы 2,5 pt под освещённой частью.
    static let lightRim: CGFloat = 1.6
}
