import Testing
import Foundation
@testable import LightPlanUI
import LightPlanCore
import LightPlanData
import LightPlanDomain

/// 31.6 на новом API (на `c7b1256b` не собирается): окно формы по времени съёмки, длина золотого часа в строке дня месяца,
/// рассвет — кнопка в виде «Без блоков», две рассветные съёмки — слова предупреждения.
@MainActor
@Suite(.enabled(if: catalogCompiled, "каталог не скомпилирован: запускать через xcodebuild test"))
struct DawnRestNewTests {

    /// П. 4: время съёмки утреннее (до конца утреннего золотого часа) — утреннее окно; его небо плохое — вечернее.
    @Test("окно формы: утреннее время — утреннее окно, а при дожде на рассвете — вечернее")
    func formWindowFollowsTheShootTime() async throws {
        let sun = DawnRestTests.sun
        let dry = DawnRestTests.app(DawnRestTests.Rain(wet: 0...0))
        await dry.light.weather.settled()
        #expect(dry.formLight(on: DawnRestTests.day, start: 360)?.dawn == true)
        #expect(dry.formLight(on: DawnRestTests.day, start: 720)?.dawn == false)
        #expect(dry.formLight(on: DawnRestTests.day)?.start == sun.goldenB, "без времени — вечернее, как было")
        let wetDawn = DawnRestTests.app(DawnRestTests.morningRain)
        await wetDawn.light.weather.settled()
        let w = try #require(wetDawn.formLight(on: DawnRestTests.day, start: 360))
        #expect(!w.poor && !w.dawn && w.start == sun.goldenB)
    }

    /// П. 8: длина золотого часа в строке месяца — вечерняя всегда (туман у заката её больше не подменяет).
    @Test("строка месяца: золотой час — вечерний, от +6° до заката")
    func monthGoldenLengthIsTheEvening() throws {
        let sun = DawnRestTests.sun
        let set = try #require(sun.set), goldenB = try #require(sun.goldenB)
        #expect(PlannerDayPanel.goldenMinutes(sun) == set - goldenB)
    }

    /// П. 15: основание дуги — кнопка: закат всегда, рассвет — пока он этих суток; одно правило у обоих видов купола.
    @Test("рассвет у дуги — кнопка и в виде «Без блоков», пока это рассвет смотримых суток")
    func riseBaseIsAButton() {
        #expect(LightScreenView.baseIsButton(.dawn, riseIsToday: true))
        #expect(!LightScreenView.baseIsButton(.dawn, riseIsToday: false))
        #expect(LightScreenView.baseIsButton(.sunset, riseIsToday: false))
    }

    /// П. 16: слова предупреждения двух рассветных съёмок — пара закатных.
    @Test("две съёмки на рассвет: «Обе съёмки просят рассвет»")
    func twoDawnShootsWords() {
        let app = DawnRestTests.app(DawnRestTests.Rain(wet: 0...0), wishes: [.sunrise])
        var other = app.snapshot.sessions[0]
        other.id = "am2"; other.start = 480; other.end = 540
        app.snapshot.sessions.append(other)
        let clash = Overlaps.clashes(ofSessionAt: 1, sessions: app.snapshot.sessions, blocks: [], context: app.clashContext).first
        #expect(clash?.kind == .bothSunrise)
        guard let clash else { return }
        let w = app.clashWords(clash)
        #expect(w.title == "Обе съёмки просят рассвет")
        #expect(w.message.contains("тоже ждёт рассвет"), "\(w.message)")
    }

    /// П. 17: строка AR «после рассвета N».
    @Test("AR: «после рассвета 20 мин»")
    func arAfterSunriseWords() {
        #expect(Lexicon("ru").t("ar.afterSunrise", ["d": "20 мин"]) == "после рассвета 20 мин")
    }
}
