import CoreGraphics
import Testing
import LightPlanCore
@testable import LightPlanUI

/// Геометрия купола против ручного разбора формул веба.
///
/// Полного стенда сверки с `node tools/shot.js` купол ещё не завёл (план,
/// итерация 18, «не проверено» — тот же пробел, что таймбар оставил после
/// себя итерацией 17): здесь только числа, которые можно проверить без
/// браузера — контрольные точки дуги и клампы, для которых формула веба
/// разобрана вручную и число сверено с её же комментарием.
struct DomeGeometryTests {

    // MARK: - posOn: дуга между двумя моментами

    @Test func posOnEndpointsAndZenith() {
        let rise = 360.0, set = 1080.0   // 06:00…18:00, солнце светит 12 часов
        let left = DomeGeometry.posOn(rise, rise, set)
        let right = DomeGeometry.posOn(set, rise, set)
        let top = DomeGeometry.posOn((rise + set) / 2, rise, set)

        #expect(abs(left.x - (DomeGeometry.cx - DomeGeometry.rx)) < 1e-9)
        #expect(abs(left.y - DomeGeometry.cy) < 1e-9)
        #expect(abs(right.x - (DomeGeometry.cx + DomeGeometry.rx)) < 1e-9)
        #expect(abs(right.y - DomeGeometry.cy) < 1e-9)
        #expect(abs(top.x - DomeGeometry.cx) < 1e-9)
        #expect(abs(top.y - (DomeGeometry.cy - DomeGeometry.ry)) < 1e-9)
    }

    // MARK: - geoDegrees: высота купола минус толщина подложки

    @Test func geoDegreesAtHorizonAndZenith() {
        let horizon = CGPoint(x: DomeGeometry.cx, y: DomeGeometry.cy)
        let zenith = CGPoint(x: DomeGeometry.cx, y: DomeGeometry.cy - DomeGeometry.ry)
        #expect(abs(DomeGeometry.geoDegrees(horizon) - (-DomeGeometry.glass)) < 1e-9)
        #expect(abs(DomeGeometry.geoDegrees(zenith) - (90 - DomeGeometry.glass)) < 1e-9)
    }

    // MARK: - deepOf: плотность просвечивающего пятна ушедшего светила

    @Test func deepOfMatchesWebComment() {
        // На горизонте пятна ещё нет вовсе.
        #expect(DomeGeometry.deepOf(0) == 0)
        // «на -9°: 0.333 → 0.667» — то самое место, где кривая садится на пол.
        #expect(abs(DomeGeometry.deepOf(-9) - DomeGeometry.ghostFloor) < 1e-9)
        // На -6° старый спад и пол сходятся: 0.34 × 2/3 ≈ 0.227 в плотности,
        // но сама доля деепОf там равна ровно полу.
        #expect(abs(DomeGeometry.deepOf(-6) - DomeGeometry.ghostFloor) < 1e-9)
        // Глубже -12° пол держит плотность всю ночь, включая -18° и дальше.
        #expect(abs(DomeGeometry.deepOf(-12) - DomeGeometry.ghostFloor) < 1e-9)
        #expect(abs(DomeGeometry.deepOf(-18) - DomeGeometry.ghostFloor) < 1e-9)
        #expect(abs(DomeGeometry.deepOf(-40) - DomeGeometry.ghostFloor) < 1e-9)
        // Между 0 и -3° пятно ещё не село на пол: ровно −e/3.
        #expect(abs(DomeGeometry.deepOf(-1) - (1.0 / 3)) < 1e-9)
    }

    // MARK: - shadeNeed: числа из комментария веба (0,11 в полдень, 0,51 в золотой час)

    @Test func shadeNeedAtNoonIsFull() {
        // Полуденный цвет (`silver`) почти сливается с листом — полная тень.
        #expect(DomeGeometry.shadeNeed(LightPalette.silver) == 1)
    }

    @Test func shadeNeedAtGoldenHourIsZero() {
        // Золотой час держит свой цвет — тень не нужна вовсе.
        #expect(DomeGeometry.shadeNeed(LightPalette.gold) == 0)
    }

    // MARK: - posAt: непрерывность на границе дуги и полярный портал

    @Test func posAtContinuousAtArcBoundary() {
        let day = SolarDay(date: CivilDate(year: 2026, month: 6, day: 21), latitude: 53.3481, longitude: 83.7798, utcOffsetHours: 7)
        guard let rise = day.rise, let set = day.set else {
            Issue.record("ожидались обычные сутки в Барнауле на солнцестояние")
            return
        }
        // Правый конец дуги: значение чуть раньше и чуть позже заката должно
        // сходиться к одной точке — иначе на стыке дня и ночи будет скачок.
        let before = DomeGeometry.posAt(set - 0.001, sun: day)
        let atSet = DomeGeometry.posAt(set, sun: day)
        let after = DomeGeometry.posAt(set + 0.001, sun: day)
        #expect(abs(before.x - atSet.x) < 0.01 && abs(before.y - atSet.y) < 0.01)
        #expect(abs(after.x - atSet.x) < 0.01 && abs(after.y - atSet.y) < 0.01)
        _ = rise
    }

    @Test func polarDayHoldsBodyInUpperHalf() {
        // 90° с.ш. на солнцестояние — полярный день: тело не ныряет под линию.
        let day = SolarDay(date: CivilDate(year: 2026, month: 6, day: 21), latitude: 90, longitude: 0, utcOffsetHours: 0)
        #expect(day.polar == .day)
        for t in stride(from: day.mint, through: day.maxt, by: 120) {
            let p = DomeGeometry.posAt(t, sun: day)
            #expect(p.y <= CGFloat(DomeGeometry.cy) + 0.01, "тело полярного дня ушло ниже горизонта на t=\(t)")
        }
    }
}
