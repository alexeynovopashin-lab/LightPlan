import Testing
import Foundation
@testable import LightPlanUI

/// Главы настроек после шага 30.5г: всё про Календарь iPhone — в своей главе «Календарь» сразу за «Съёмками».
struct SettingsChaptersTests {
    typealias Chapter = SettingsView.Chapter

    @Test func calendarChapterStandsRightAfterShoots() {
        let order = Chapter.allCases
        let i = try! #require(order.firstIndex(of: .shoots))
        #expect(order[i + 1] == .calendar)
        #expect(order.filter { $0 == .calendar }.count == 1)
        #expect(order.map(\.rawValue) == ["profile", "view", "shoots", "calendar", "alerts", "places", "store", "data", "network", "locale", "about"])
    }

    @Test func calendarChapterHoldsTheMirrorTheGhostsAndTheDimmedIcsImport() {
        // Зеркало, «Другие календари» и списки галочек — одна секция; импорт .ics приглушён, как был в «Данных».
        #expect(Chapter.calendar.parts == [.calendarSection, .foreign("set.icsImport")])
    }

    @Test func shootsAndDataNoLongerHoldAnythingCalendar() {
        #expect(!Chapter.shoots.parts.contains(.calendarSection))
        #expect(!Chapter.data.parts.contains(.calendarSection))
        #expect(!Chapter.data.parts.contains(.foreign("set.icsImport")))
        #expect(Chapter.data.parts == [.foreign("set.data"), .foreign("cloud.title")])      // остальное «Данных» на месте
    }

    @Test func theChapterIsNamedCalendarInEveryLanguageWithAnIconFromTheLibrary() throws {
        #expect(Chapter.calendar.titleKey == "set.calendar")
        #expect(Chapter.calendar.icon == "view_month")
        let names = ["ru": "Календарь", "en": "Calendar", "es": "Calendario", "ja": "カレンダー", "zh": "日历"]
        for (lang, name) in names {
            #expect(Lexicon(lang).t("set.calendar") == name, Comment(rawValue: lang))
        }
        // Значок есть в библиотеке знаков: рисовать новый не пришлось.
        #expect(IconLibrary.common["view_month"] != nil)
    }

    @Test func everyChapterStillHasATitleAndAnIcon() {
        for ch in Chapter.allCases { #expect(!ch.titleKey.isEmpty && !ch.icon.isEmpty) }
    }
}
