import Testing
import SwiftUI
import Foundation
import LightPlanDomain
import LightPlanCore
@testable import LightPlanUI
#if os(iOS)
import UIKit

/// Шаги 30б.2в-1 и 30б.2в-2: живые виды виджета (`LightPlanWidget/Views/`: `MediumLiveView`, `SmallLiveView`, `LargeView`,
/// `LockCircularView`, `LockRectangularView`, их разбор дня `DayPlan`, корень `WidgetRoot`) отрисованы по числам, как в
/// `WidgetViewsTests`: содержимое плашки (с её собственными полями — у колец они несут деления) помещается в плашку 158 / 170
/// (малый), 338 × 158 / 364 × 170 (средний), 338 × 354 / 364 × 382 (большой) в трёх размерах текста; двоеточие отсчёта стоит по
/// середине цифр (мерено по пикселям); имена клиентов есть только на «Домой»; знаки точек расширения совпадают со знаками приложения.
@MainActor
struct WidgetLiveTests {

    private let tomsk = WidgetFeed.Spot(name: "Томск", latitude: 56.4977, longitude: 84.9744, zone: "Asia/Tomsk")
    /// Часы Томска (UTC+7) 24.10.2026 плюс `day`.
    private func tsk(_ h: Int, _ m: Int = 0, day d: Int = 24) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.addingTimeInterval(-7 * 3600)
    }
    private func ms(_ d: Date) -> Int64 { Moment(d).milliseconds }

    /// Знак точки так, как его кладёт в файл приложение (`PointSign.name`, студия — по ссылке на неё).
    private func stop(_ at: Date, _ name: String, _ place: String = "", studio: Bool = false) -> WidgetFeed.Stop {
        .init(at: ms(at), name: name, place: place, sign: PointSign.name(for: name, place: place, studio: studio))
    }

    /// Сценарий Алексея: свадьба 12:00–00:30, «Пара в студии» до 13:54 (студийный час), дальше «Обед 14:00», «Прогулка 15:00».
    private var wedding: WidgetFeed.Shoot {
        .init(id: "w", start: ms(tsk(12)), end: ms(tsk(0, 30, day: 25)), title: "Свадьба", place: "Томск", wantsSunset: true,
              rents: [.init(from: ms(tsk(12)), to: ms(tsk(14)), deadline: ms(tsk(13, 54)), studio: "Томсон")],
              stops: [stop(tsk(12), "Пара в студии", "Студия «Томсон»", studio: true),
                      stop(tsk(14), "Обед", "Кафе «Вилка»"),
                      stop(tsk(15), "Прогулка", "Набережная реки Ушайки"),
                      stop(tsk(17), "Церемония", "Дворец бракосочетания"),
                      stop(tsk(19), "Банкет", "Ресторан «Дом»"),
                      stop(tsk(22), "Танцы", "Ресторан «Дом»")],
              genre: "wedding", names: "Анна+Игорь")
    }

    private func frame(at: Date, shoots: [WidgetFeed.Shoot]? = nil) -> WidgetFrame {
        WidgetFeed(place: tomsk, shoots: shoots ?? [wedding]).frame(at: at)
    }

    private var now: WidgetFrame { frame(at: tsk(12, 52)) }

    // MARK: Разбор дня

    @Test func theDayPlanReadsTheScenario() throws {
        let plan = try #require(DayPlan(now))
        #expect(plan.stops.count == 6)
        #expect(plan.current?.name == "Пара в студии")
        #expect(plan.pointEnd == tsk(13, 54), "точка кончается студийным часом, а не началом «Обеда»")
        #expect(abs(plan.pointLeft! - 62 * 60) < 0.01, "12:52 → 13:54")
        #expect(abs(plan.shootLeft - (11 * 60 + 38) * 60) < 0.01, "12:52 → 00:30")
        #expect(plan.upcomingStops.map(\.name).prefix(2) == ["Обед", "Прогулка"])
        #expect(plan.short(plan.pointLeft!) == "62 мин")
        #expect(plan.hours(plan.shootLeft) == "11 ч", "целые часы вниз")
        #expect(plan.long(plan.shootLeft) == "11 ч 38 мин")
        var bare = wedding
        bare.names = nil
        var blank = wedding
        blank.names = ""
        #expect(plan.title == "Свадьба Анна+Игорь" && DayPlan(frame(at: tsk(12, 52), shoots: [bare]))?.title == "Свадьба"
                && DayPlan(frame(at: tsk(12, 52), shoots: [blank]))?.title == "Свадьба")
        #expect(abs(plan.shootProgress - (52.0 / 750.0)) < 1e-9, "52 минуты из 12 ч 30 мин")
        #expect(abs((plan.pointProgress ?? -1) - 52.0 / 114.0) < 1e-9)
        #expect(plan.shootHourMarks.count == 12, "12 часовых отметок на 12,5 часа")
        #expect(plan.pointQuarterMarks.count == 7, "114 минут: 15, 30 … 105")
        // В 13:00 остаток точки — «54 мин», как в словах Алексея.
        let at13 = try #require(DayPlan(frame(at: tsk(13))))
        #expect(at13.short(at13.pointLeft!) == "54 мин")
        #expect(at13.hours(at13.shootLeft) == "11 ч")
    }

    /// Ревью GPT к 8d3f1c2: незакрытая вручную съёмка после записанного конца. Кольцо не застывает — все его числа уже на пределе
    /// (остаток 0, доли 1) и в любой момент после конца одни и те же, так что минутные записи ленты ничего бы не меняли.
    @Test func anOpenShootPastItsEndHasNothingLeftToCount() throws {
        var open = wedding
        open.open = true
        let a = try #require(DayPlan(frame(at: tsk(1, 10, day: 25), shoots: [open])))
        let b = try #require(DayPlan(frame(at: tsk(5, 45, day: 25), shoots: [open])))
        for p in [a, b] {
            #expect(p.shootLeft == 0 && p.pointLeft == 0 && p.shootProgress == 1 && p.pointProgress == 1)
            #expect(p.hours(p.shootLeft) == "0 мин" && p.short(p.pointLeft!) == "0 мин")
        }
        #expect(a.shootHourMarks == b.shootHourMarks && a.pointQuarterMarks == b.pointQuarterMarks)
    }

    @Test func theLastPointEndsWithTheShootAndHoursGiveWayToMinutes() throws {
        let late = try #require(DayPlan(frame(at: tsk(23, 50))))
        #expect(late.current?.name == "Танцы")
        #expect(late.pointEnd == tsk(0, 30, day: 25), "последняя точка кончается с съёмкой")
        #expect(late.upcomingStops.isEmpty)
        #expect(late.hours(late.shootLeft) == "40 мин", "в последний час — минуты")
        let noRent = try #require(DayPlan(frame(at: tsk(15, 20))))
        #expect(noRent.current?.name == "Прогулка" && noRent.pointEnd == tsk(17), "без студии точка идёт до следующей")
    }

    /// Ревью GPT к d52f3e3: студийный час кончается в 13:54, следующая точка «Обед» в 14:00. После 13:54 студийного отсчёта нет, и точка
    /// «Пара в студии» кончалась «Обедом»: остаток прыгал с «1 мин» на «6 мин», внутреннее кольцо шло назад (0,9912 → 0,9500 → 0,9917).
    /// Раз студия началась, точка кончается меньшим из «студийный час, следующая точка» весь свой отрезок.
    @Test func theStudioPointStopsAtItsDeadlineAndNeverGoesBack() throws {
        func plan(_ h: Int, _ m: Int) throws -> DayPlan { try #require(DayPlan(frame(at: tsk(h, m)))) }
        let before = try plan(13, 53)
        #expect(before.pointEnd == tsk(13, 54) && before.short(before.pointLeft!) == "1 мин")
        var last = -1.0
        for minute in 0..<120 {
            let p = try #require(DayPlan(frame(at: tsk(12).addingTimeInterval(Double(minute) * 60))))
            let v = try #require(p.pointProgress)
            #expect(v >= last, "12:00 + \(minute) мин: кольцо точки пошло назад, \(last) → \(v)")
            last = v
        }
        for (h, m) in [(13, 54), (13, 57), (13, 59)] {
            let p = try plan(h, m)
            #expect(p.current?.name == "Пара в студии" && p.pointEnd == tsk(13, 54), "\(h):\(m)")
            #expect(p.pointLeft == 0 && p.short(p.pointLeft!) == "0 мин", "\(h):\(m): остаток точки \(String(describing: p.pointLeft))")
            #expect(p.pointProgress == 1, "\(h):\(m): внутреннее кольцо полное, а не \(String(describing: p.pointProgress))")
        }
        // Внешнее кольцо (вся съёмка) студийного часа не знает: 13:59 — 119 минут из 12 ч 30 мин.
        let late = try plan(13, 59)
        #expect(abs(late.shootProgress - 119.0 / 750.0) < 1e-9 && late.shootLeft == 631 * 60)
        #expect(late.hours(late.shootLeft) == "10 ч" && late.shootHourMarks.count == 12)
        // «Обед» в 14:00: студия осталась позади (её час кончился до начала точки) — точка идёт до «Прогулки».
        let lunch = try plan(14, 30)
        #expect(lunch.current?.name == "Обед" && lunch.pointEnd == tsk(15) && lunch.short(lunch.pointLeft!) == "30 мин")
        // Студия, которая ещё не началась, точку не сокращает; началась — сокращает до своего часа.
        var late13 = wedding
        late13.rents = [.init(from: ms(tsk(13)), to: ms(tsk(13, 30)), deadline: ms(tsk(13, 24)), studio: "Томсон")]
        func end(_ h: Int, _ m: Int) throws -> Date? { try #require(DayPlan(frame(at: tsk(h, m), shoots: [late13]))).pointEnd }
        #expect(try end(12, 30) == tsk(14), "студия впереди")
        #expect(try end(13, 10) == tsk(13, 24), "студия идёт")
        #expect(try end(13, 40) == tsk(13, 24), "студия кончилась, точка нет")
        // Студия кончается позже следующей точки: пока она идёт, точка кончается следующей.
        var long = wedding
        long.rents = [.init(from: ms(tsk(12)), to: ms(tsk(15)), deadline: ms(tsk(14, 30)), studio: "Томсон")]
        #expect(try #require(DayPlan(frame(at: tsk(13), shoots: [long]))).pointEnd == tsk(14))
    }

    /// Та же свадьба на сутки позже: воскресенье 25.10, точки в те же часы.
    private var sundayWedding: WidgetFeed.Shoot {
        var sunday = wedding
        let day: Int64 = 86_400_000
        sunday.start += day; sunday.end += day
        sunday.rents = wedding.rents.map { .init(from: $0.from + day, to: $0.to + day, deadline: $0.deadline + day, studio: $0.studio) }
        sunday.stops = wedding.stops.map { .init(at: $0.at + day, name: $0.name, place: $0.place, sign: $0.sign) }
        return sunday
    }

    /// Шапка большого вида называет день, который рисует: накануне — «Завтра» и дата съёмки (слово то же, что на малом и среднем),
    /// в тот же день — просто дата; идущая за полночь съёмка — сегодняшняя дата.
    @Test func theLargeHeaderNamesTheDayOfTheShootItDraws() throws {
        func line(_ f: WidgetFrame) throws -> String { try #require(DayPlan(f)).dateLine }
        #expect(try line(frame(at: tsk(20), shoots: [sundayWedding])) == "Завтра · воскресенье, 25 октября")
        #expect(try line(frame(at: tsk(5, day: 25), shoots: [sundayWedding])) == "Воскресенье, 25 октября")
        #expect(try line(now) == "Суббота, 24 октября")
        #expect(try line(frame(at: tsk(0, 20, day: 25))) == "Воскресенье, 25 октября", "идущая за полночь — сегодняшняя дата")
        let eve = try #require(DayPlan(frame(at: tsk(20), shoots: [sundayWedding])))
        #expect(eve.primary.day == tomsk.light(on: CivilDate(year: 2026, month: 10, day: 25)))
    }

    /// Ревью GPT к d52f3e3: накануне вечером (суббота 20:00, свадьба в воскресенье в 12:00) большой вид рисует воскресную съёмку, и свет
    /// под ней должен быть воскресным. По пикселям: всё ниже шапки в субботу вечером — то же изображение, что воскресным утром (точки те же,
    /// светила ещё не взошли), а у той же свадьбы в субботу — другое (проверка не пустая).
    @Test func theLargeViewBeforeTheShootDrawsTheLightOfTheShootsDay() throws {
        func below(_ f: WidgetFrame) throws -> Data {
            let r = ImageRenderer(content: LargeView(frame: f).frame(width: 364, height: 382).background(Color.white).environment(\.colorScheme, .light))
            r.scale = 2
            let cg = try #require(r.uiImage?.cgImage)
            let crop = try #require(cg.cropping(to: CGRect(x: 0, y: 120, width: cg.width, height: cg.height - 120)))
            return try #require(UIImage(cgImage: crop).pngData())
        }
        let sunday = sundayWedding
        let eve = frame(at: tsk(20), shoots: [sunday])
        #expect(eve.kind == .upcoming && eve.primary?.dayOffset == 1, "накануне вечером на плашке воскресная съёмка")
        let sundayLight = try below(frame(at: tsk(5, day: 25), shoots: [sunday]))
        #expect(try below(eve) == sundayLight, "свет под воскресной съёмкой — воскресный")
        #expect(try below(frame(at: tsk(5), shoots: [wedding])) != sundayLight, "субботний свет от воскресного отличается")
    }

    @Test func aShootWithoutStopsHasNoRingForThePointButDoesNotCrash() throws {
        let bare = WidgetFeed.Shoot(id: "b", start: ms(tsk(12)), end: ms(tsk(15)), title: "Портрет", place: "Парк")
        let f = frame(at: tsk(13), shoots: [bare])
        let plan = try #require(DayPlan(f))
        #expect(plan.current == nil && plan.pointLeft == nil && plan.pointProgress == nil && plan.pointQuarterMarks.isEmpty)
        #expect(ideal(MediumLiveView(frame: f), width: 364, type: .large).height <= 170)
        #expect(ideal(SmallLiveView(frame: f), width: 170, type: .large).height <= 170)
    }

    // MARK: Деления по периметру

    @Test func theTicksWalkTheOutlineClockwiseFromTheTopCentre() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        let w = PerimeterWalker(rect: rect, radius: 10)
        let expected: CGFloat = 2 * (100 - 20) + 2 * (60 - 20) + 2 * .pi * 10
        #expect(abs(w.length - expected) < 0.001, "периметр \(w.length) против \(expected)")
        let start = w.sample(0)
        #expect(start.point == CGPoint(x: 50, y: 0) && start.inward == CGVector(dx: 0, dy: 1), "середина верха, внутрь — вниз")
        let right = w.sample(40 + 10 * .pi / 2 + 20)   // середина правой стороны
        #expect(abs(right.point.x - 100) < 0.001 && abs(right.point.y - 30) < 0.001 && right.inward == CGVector(dx: -1, dy: 0))
        let end = w.sample(w.length)
        #expect(abs(end.point.x - 50) < 0.001 && abs(end.point.y) < 0.001, "обход замыкается в начале")
        // Все деления лежат внутри прямоугольника и смотрят в его сторону.
        for i in 0..<200 {
            let s = w.sample(CGFloat(i) / 200 * w.length)
            let tip = CGPoint(x: s.point.x + s.inward.dx * 5, y: s.point.y + s.inward.dy * 5)
            #expect(rect.insetBy(dx: -0.001, dy: -0.001).contains(s.point) && rect.insetBy(dx: -0.001, dy: -0.001).contains(tip))
        }
    }

    // MARK: Влезает ли

    private func ideal<V: View>(_ v: V, width: CGFloat, type: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(rootView: v.environment(\.dynamicTypeSize, type).frame(width: width).fixedSize(horizontal: false, vertical: true))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private static let types: [(String, DynamicTypeSize)] = [("обычный", .large), ("крупный", .xxLarge), ("огромный", .accessibility3)]

    /// Кадры «живого» дня для среднего и малого: студийный час, точка без студии, последняя точка.
    private func liveFrames() -> [(String, WidgetFrame)] {
        [("студийный час", now), ("точка без студии", frame(at: tsk(15, 20))), ("последняя точка", frame(at: tsk(23, 50)))]
    }

    @Test func mediumLiveFitsInThreeTextSizes() {
        var report: [String] = []
        for (w, h) in [(338.0, 158.0), (364.0, 170.0)] {
            for (name, f) in liveFrames() {
                for (tn, t) in Self.types {
                    for alpha in [false, true] {
                        let size = ideal(MediumLiveView(frame: f, alpha: alpha), width: w, type: t)
                        report.append(String(format: "средний %.0f «%@» %@ α=%d: высота %.1f из %.0f", w, name, tn, alpha ? 1 : 0, size.height, h))
                        #expect(size.height <= h, Comment(rawValue: report.last!))
                    }
                }
            }
        }
        print(report.joined(separator: "\n"))
    }

    @Test func smallLiveFitsInThreeTextSizes() {
        var report: [String] = []
        for side in [158.0, 170.0] {
            for (name, f) in liveFrames() {
                for (tn, t) in Self.types {
                    for alpha in [false, true] {
                        let size = ideal(SmallLiveView(frame: f, alpha: alpha), width: side, type: t)
                        report.append(String(format: "малый %.0f «%@» %@ α=%d: высота %.1f из %.0f", side, name, tn, alpha ? 1 : 0, size.height, side))
                        #expect(size.height <= side, Comment(rawValue: report.last!))
                    }
                }
            }
        }
        print(report.joined(separator: "\n"))
    }

    private func largeFrames() -> [(String, WidgetFrame)] {
        let polar = WidgetFeed(place: .init(name: "Tromsø", latitude: 69.6496, longitude: 18.956, zone: "Europe/Oslo"))
            .frame(at: Date(timeIntervalSince1970: 1_782_043_200))
        return liveFrames() + [("до начала", frame(at: tsk(11))), ("накануне вечером", frame(at: tsk(20), shoots: [sundayWedding])),
                               ("без съёмок", frame(at: tsk(12, 52), shoots: [])),
                               ("без съёмок, вечер", frame(at: tsk(20), shoots: [])), ("полярный день", polar)]
    }

    @Test func largeFitsInThreeTextSizes() {
        var report: [String] = []
        for (w, h) in [(338.0, 354.0), (364.0, 382.0)] {
            for (name, f) in largeFrames() {
                for (tn, t) in Self.types {
                    let size = ideal(LargeView(frame: f, alpha: true), width: w, type: t)
                    report.append(String(format: "большой %.0f «%@» %@: высота %.1f из %.0f", w, name, tn, size.height, h))
                    #expect(size.height <= h, Comment(rawValue: report.last!))
                }
            }
        }
        print(report.joined(separator: "\n"))
    }

    @Test func lockWidgetsFitTheirPlates() {
        // Экран блокировки: круглый 76 × 76, прямоугольный 172 × 76 (iPhone 15 Pro Max; на 14 — 72 и 160).
        for (w, h) in [(160.0, 72.0), (172.0, 76.0)] {
            for (name, f) in liveFrames() + [("без съёмок", frame(at: tsk(12, 52), shoots: [])), ("до начала", frame(at: tsk(11)))] {
                for (tn, t) in Self.types {
                    let size = ideal(LockRectangularView(frame: f), width: w, type: t)
                    #expect(size.height <= h, Comment(rawValue: "прямоугольный \(w) «\(name)» \(tn): \(size.height) > \(h)"))
                    let c = ideal(LockCircularView(frame: f), width: h, type: t)
                    #expect(c.height <= h, Comment(rawValue: "круглый \(h) «\(name)» \(tn): \(c.height) > \(h)"))
                }
            }
        }
    }

    // MARK: Что где стоит и чего нет на экране блокировки

    @Test func theRingStandsOnlyWhileTheShootGoes() {
        // Смотреть можно только на кадр: выбор вида — `frame.kind == .live`.
        #expect(now.kind == .live && frame(at: tsk(11)).kind == .upcoming && frame(at: tsk(12, 52), shoots: []).kind == .light)
    }

    /// Имена клиентов — только на «Домой» (Алексей, 25.10): на экране блокировки их нет ни в одной строке ни одного вида.
    @Test func clientNamesAreOnlyOnTheHomeScreen() throws {
        // Текст «Домой» читается из тех же данных, что и подписи: заголовок плашки несёт имена.
        let plan = try #require(DayPlan(now))
        #expect(plan.title == "Свадьба Анна+Игорь")
        // Экран блокировки: строки видов и текст круга — целиком, без «Анна» и «Игорь».
        let lock = LockRectangularView(frame: now).lines + [LockCircularView(frame: now).label ?? ""] + [LockInlineView(frame: now, alpha: false).line]
        #expect(!lock.joined(separator: "|").contains("Анна") && !lock.joined(separator: "|").contains("Игорь"), Comment(rawValue: "\(lock)"))
        #expect(LockRectangularView(frame: now).lines == ["12:00–13:54", "Свадьба", "Студия «Томсон»"])
        // Тот же кадр, но жанра нет в словаре и имена длинные: ничего нового в строках не появляется.
        var long = wedding
        long.names = "Анна-Мария+Игорь-Александр"
        let f = frame(at: tsk(12, 52), shoots: [long])
        #expect(LockRectangularView(frame: f).lines == ["12:00–13:54", "Свадьба", "Студия «Томсон»"])
        // По пикселям: тот же кадр без имён рисуется на блокировке тем же изображением, на «Домой» — другим (проверка не пустая).
        var bare = wedding
        bare.names = nil
        let nameless = frame(at: tsk(12, 52), shoots: [bare])
        func png(_ shape: WidgetShape, _ f: WidgetFrame, _ w: CGFloat, _ h: CGFloat) -> Data? {
            let r = ImageRenderer(content: WidgetRoot(frame: f, shape: shape, alpha: false).frame(width: w, height: h)
                .background(Color.black).environment(\.colorScheme, .dark))
            r.scale = 2
            return r.uiImage?.pngData()
        }
        for (shape, w, h) in [(WidgetShape.circular, 76.0, 76.0), (.rectangular, 172, 76), (.inline, 172, 24)] {
            let a = png(shape, now, w, h), b = png(shape, nameless, w, h)
            #expect(a != nil && a == b, "\(shape): имена изменили картинку экрана блокировки")
        }
        for (shape, w, h) in [(WidgetShape.small, 170.0, 170.0), (.medium, 364, 170), (.large, 364, 382)] {
            #expect(png(shape, now, w, h) != png(shape, nameless, w, h), "\(shape): «Домой» имён не показывает")
        }
    }

    @Test func theLockScreenSaysOnlyGenrePointTimeAndPlace() {
        // Текст экрана блокировки сверяется целиком (ревью GPT к 6b15258): имён клиентов нет ни в одной строке, а если вид
        // заведёт новую строку, этот тест покраснеет.
        let rect = LockRectangularView(frame: now).lines
        #expect(rect == ["12:00–13:54", "Свадьба", "Студия «Томсон»"], Comment(rawValue: "\(rect)"))
        #expect(!rect.joined().contains("Анна") && !rect.joined().contains("Игорь"))
        #expect(LockCircularView(frame: now).label == "4:10", Comment(rawValue: "\(String(describing: LockCircularView(frame: now).label))"))
        #expect(LockCircularView(frame: frame(at: tsk(18, 30))).label == nil, "после золотого часа круг без цифр")
        // Без съёмок прямоугольник — ближайший свет тем же рисунком, а не прочерк.
        let free = frame(at: tsk(12, 52), shoots: [])
        #expect(LockRectangularView(frame: free).lines.count == 3 && LockRectangularView(frame: free).lines[1] == "Закат", Comment(rawValue: "\(LockRectangularView(frame: free).lines)"))
    }

    @Test func captionsFollowTheGenre() throws {
        let portrait = WidgetFeed.Shoot(id: "p", start: ms(tsk(12)), end: ms(tsk(15)), title: "Портрет", place: "Парк",
                                        stops: [.init(at: ms(tsk(12)), name: "Парк")], genre: "portrait")
        let w = try #require(DayPlan(now)), p = try #require(DayPlan(frame(at: tsk(13), shoots: [portrait])))
        #expect(w.untilShoot == "до конца свадьбы" && w.shootNoun == "свадьба")
        #expect(p.untilShoot == "до конца съёмки" && p.shootNoun == "съёмка")
        // Жанра в файле старого вида нет — общее слово, не «свадьба».
        var old = wedding
        old.genre = nil
        let o = try #require(DayPlan(frame(at: tsk(12, 52), shoots: [old])))
        #expect(o.untilShoot == "до конца съёмки")
    }

    // MARK: Знаки точек в расширении

    /// Знаки расширения (`WidgetIcons.generated.swift`) — строки библиотеки приложения, а их разбор — копия `IconArt`; чтобы копия не
    /// ушла, пути обоих сравниваются знак за знаком по всей таблице.
    @Test func theWidgetIconsAreTheAppsIcons() {
        var checked = 0
        for (name, text) in WidgetIconTable.common {
            #expect(IconLibrary.common[name] == text, "знак \(name) в таблице расширения не тот, что в приложении")
            let mine = WidgetIconArt.decode(text), theirs = IconArt.decode(text).parts
            #expect(mine.count == theirs.count, "частей у \(name)")
            for (a, b) in zip(mine, theirs) {
                let same: Bool = a.path == b.path && a.width == b.width && a.butt == b.butt
                #expect(same, "путь знака \(name)")
            }
            checked += 1
        }
        #expect(checked >= 100)
    }

    /// Какой знак ни назвало бы приложение (`PointSign` по любому правилу), в таблице расширения он есть — иначе точка получила бы кружок.
    @Test func everySignThePointRulesCanNameIsInTheWidgetTable() {
        let named = Set(IconLibrary.pointWords.map(\.sign)).filter { IconLibrary.common[$0] != nil }
        let missing = named.filter { WidgetIconTable.common[$0] == nil }
        #expect(missing.isEmpty, Comment(rawValue: "нет в расширении: \(missing.sorted())"))
        for n in ["dot", "studio", "sun", "sunrise", "sunset"] { #expect(WidgetIconTable.common[n] != nil, "нет \(n)") }
        // Неизвестное имя и отсутствие имени — кружок, не пустота.
        #expect(WidgetIconArt.parts("нет такого").count == WidgetIconArt.parts("dot").count && !WidgetIconArt.parts(nil).isEmpty)
    }

    // MARK: Двоеточие по середине цифр

    /// Рисует `v` чёрным по белому в 4-кратном масштабе и возвращает, на сколько pt середина двоеточия ниже середины цифр (минус — выше).
    /// Столбцы краски делятся на цифры (высота ≥ 0,8 от самой высокой) и двоеточия (остальные: две точки, низкие).
    private func colonDrop<V: View>(_ v: V) -> (drop: CGFloat, digits: Int, colons: Int)? {
        let r = ImageRenderer(content: v.foregroundStyle(.black).padding(6).background(Color.white))
        r.scale = 4
        guard let cg = r.uiImage?.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 255, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        func ink(_ x: Int, _ y: Int) -> Bool { px[y * w + x] < 128 }
        var runs: [(top: CGFloat, bottom: CGFloat)] = []
        var x = 0
        while x < w {
            if (0..<h).contains(where: { ink(x, $0) }) {
                var top = h, bottom = 0
                while x < w, (0..<h).contains(where: { ink(x, $0) }) {
                    for y in 0..<h where ink(x, y) { top = min(top, y); bottom = max(bottom, y) }
                    x += 1
                }
                runs.append((CGFloat(top), CGFloat(bottom)))
            } else { x += 1 }
        }
        let tallest = runs.map { $0.bottom - $0.top }.max() ?? 0
        let digits = runs.filter { $0.bottom - $0.top >= tallest * 0.8 }
        let colons = runs.filter { $0.bottom - $0.top < tallest * 0.8 }
        guard !digits.isEmpty, !colons.isEmpty else { return (0, digits.count, colons.count) }
        let mid = (digits.map(\.top).min()! + digits.map(\.bottom).max()!) / 2
        let colonMid = (colons.map(\.top).min()! + colons.map(\.bottom).max()!) / 2
        return ((colonMid - mid) / 4, digits.count, colons.count)
    }

    @Test func theColonSitsInTheMiddleOfTheDigits() throws {
        var report: [String] = []
        for size in [21.0, 28.0, 34.0] {
            let lifted = try #require(colonDrop(ColonCount(seconds: (4 * 60 + 10) * 60, size: size)))
            #expect(lifted.digits == 3 && lifted.colons == 1, "в «4:10» три цифры и одно двоеточие: \(lifted)")
            // «Было» — как стояло в студийном таймере до 25.10: двоеточие отдельным видом.
            let f = Font.system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
            let flat = try #require(colonDrop(HStack(spacing: 0) { Text("4"); Text(":"); Text("10") }.font(f)))
            report.append(String(format: "кегль %.0f: двоеточие ниже середины цифр — отдельным видом %+.2f pt, одной строкой (`ColonCount`) %+.2f pt",
                                 size, flat.drop, lifted.drop))
            #expect(abs(lifted.drop) <= 0.35, Comment(rawValue: report.last!))
            // Проверка не пустая: отдельным видом двоеточие заметно ниже.
            #expect(flat.drop >= 1.0, "отдельным видом двоеточие ниже середины на \(flat.drop) pt — иначе проверка ничего не доказывает")
        }
        print(report.joined(separator: "\n"))
    }

    /// Не утверждение, а замер для отчёта: где стоит двоеточие в системном `Text(timerInterval:)` (его рисует система, подъём не применить).
    @Test func measuresTheSystemTimerColonForTheRecord() {
        let a = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for size in [21.0, 34.0] {
            let timer = Text(timerInterval: a...a.addingTimeInterval(4 * 3600 + 10 * 60), countsDown: true, showsHours: true)
                .font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
            let m = colonDrop(timer)
            print("системный отсчёт, кегль \(size): \(m.map { String(format: "двоеточие ниже середины цифр на %+.2f pt (цифр %d, двоеточий %d)", $0.drop, $0.digits, $0.colons) } ?? "не отрисован")")
        }
    }

    // MARK: Снимки построенных видов

    private let darkPlate = Color(red: 0.059, green: 0.055, blue: 0.047)
    private let lightPlate = Color(red: 0.98, green: 0.973, blue: 0.953)

    private func plate<V: View>(_ v: V, _ w: CGFloat, _ h: CGFloat, dark: Bool) -> some View {
        v.frame(width: w, height: h)
            .background(dark ? darkPlate : lightPlate)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
    }

    /// Плашка экрана блокировки: на тёмных и светлых обоях, а не на подложке виджета.
    private func lockPlate<V: View>(_ v: V, _ w: CGFloat, _ h: CGFloat, dark: Bool) -> some View {
        v.frame(width: w, height: h)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)))
            .padding(16)
            .background(LinearGradient(colors: dark ? [Color(red: 0.12, green: 0.16, blue: 0.24), Color(red: 0.05, green: 0.06, blue: 0.1)]
                                                    : [Color(red: 0.93, green: 0.86, blue: 0.74), Color(red: 0.85, green: 0.9, blue: 0.95)],
                                       startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func cell(_ caption: String, _ w: CGFloat, _ content: some View) -> some View {
        VStack(spacing: 6) {
            content
            Text(caption).font(.system(size: 11, weight: .medium)).foregroundStyle(.white).multilineTextAlignment(.center).frame(width: w)
        }
    }

    private func sheet(_ rows: [[AnyView]], scale: CGFloat) -> UIImage? {
        let grid = VStack(spacing: 18) {
            ForEach(rows.indices, id: \.self) { r in HStack(alignment: .top, spacing: 18) { ForEach(rows[r].indices, id: \.self) { rows[r][$0] } } }
        }
        .padding(18).background(Color(red: 0.36, green: 0.35, blue: 0.33))
        let r = ImageRenderer(content: grid)
        r.scale = scale
        return r.uiImage
    }

    private func write(_ image: UIImage?, _ dir: String, _ name: String) throws {
        let png = try #require(image?.pngData(), "картинка \(name) не отрисована")
        try png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        #expect(png.count <= 300 * 1024, "\(name).png: \(png.count / 1024) КБ, предел 300")
    }

    /// Снимки построенных видов — тем же корнем, что стоит в расширении (`WidgetRoot`): в `$LP_BUILT_DIR` или `/tmp/lp-built-out`,
    /// если папка заведена (обычный прогон ничего не пишет). Лежат в `docs/30b2v_sketches/built/`.
    @Test func writesTheBuiltSheetsWhenAsked() throws {
        let dir = ProcessInfo.processInfo.environment["LP_BUILT_DIR"] ?? "/tmp/lp-built-out"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        let live = now, at13 = frame(at: tsk(13)), free = frame(at: tsk(12, 52), shoots: []), soon = frame(at: tsk(11))
        let tail = frame(at: tsk(23, 50))
        func two(_ caption: String, _ w: CGFloat, _ h: CGFloat, _ shape: WidgetShape, _ f: WidgetFrame) -> [AnyView] {
            [true, false].map { dark in
                AnyView(cell("\(caption) · \(dark ? "тёмная" : "светлая")", w, plate(WidgetRoot(frame: f, shape: shape, alpha: true), w, h, dark: dark)))
            }
        }
        try write(sheet([two("средний · идёт · 12:52", 364, 170, .medium, live), two("средний · идёт · 13:00 (остаток точки 54 мин)", 364, 170, .medium, at13),
                         two("средний · последняя точка · 23:50", 364, 170, .medium, tail)], scale: 1.5), dir, "medium")
        try write(sheet([two("средний · свет (съёмок нет)", 364, 170, .medium, free), two("средний · съёмка впереди · 11:00", 364, 170, .medium, soon)], scale: 1.5), dir, "medium_no_ring")
        try write(sheet([two("малый · идёт · 12:52", 170, 170, .small, live) + two("малый · 23:50", 170, 170, .small, tail),
                         two("малый · свет", 170, 170, .small, free) + two("малый · съёмка впереди", 170, 170, .small, soon)], scale: 2.2), dir, "small")
        try write(sheet([two("большой · день со съёмкой · 12:52", 364, 382, .large, live), two("большой · день без съёмок", 364, 382, .large, free)], scale: 1.8), dir, "large")
        try write(sheet([two("большой · накануне вечером · суббота 20:00, свадьба в воскресенье", 364, 382, .large, frame(at: tsk(20), shoots: [sundayWedding]))], scale: 1.8), dir, "large_eve")
        let night = frame(at: tsk(18, 30))
        func lockCells(_ caption: String, _ f: WidgetFrame) -> [AnyView] {
            [true, false].flatMap { dark -> [AnyView] in
                let tone = dark ? "тёмные обои" : "светлые обои"
                return [AnyView(cell("\(caption) · круглый · \(tone)", 108, lockPlate(WidgetRoot(frame: f, shape: .circular, alpha: false), 76, 76, dark: dark))),
                        AnyView(cell("\(caption) · прямоугольный · \(tone)", 204, lockPlate(WidgetRoot(frame: f, shape: .rectangular, alpha: false), 172, 76, dark: dark)))]
            }
        }
        try write(sheet([lockCells("идёт · 12:52", live), lockCells("свет · 12:52", free), lockCells("после золотого часа · 18:30", night)], scale: 1.4), dir, "lock")
    }
}
#endif
