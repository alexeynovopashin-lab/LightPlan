import Testing
@testable import LightPlanUI

/// Шаг 29.11, п. 4: корень правила не ловит слово внутри чужого слова. «Фотостудия»
/// получала бокалы (`тост`), «сделка» — ёлку (`елк`). Правила — из `beta/icons.js`
/// (`tier()` ставит границу кириллицы), здесь проверка самих знаков.
struct PointSignWordBoundaryTests {

    @Test func photoStudioIsTheStudioSign() {
        #expect(PointSign.name(for: "Фотостудия") == "studio")
        #expect(PointSign.name(for: "фотостудия Томсон") == "studio")
        #expect(PointSign.name(for: "Студия") == "studio")
    }

    @Test func rootInsideAnotherWordIsNotAMatch() {
        for w in ["простор", "востоке", "сделка", "недоступен", "британца", "прогноз", "занятость", "геолокация"] {
            #expect(PointSign.name(for: w) == "dot", "«\(w)» не должно ловить знак по корню внутри слова")
        }
    }

    @Test func realWordsStillMatch() {
        #expect(PointSign.name(for: "Тост") == "toast")
        #expect(PointSign.name(for: "Свадебный тост") == "toast")
        #expect(PointSign.name(for: "Сборы невесты") == "rings")
        // Составные с приставкой из списка — как были.
        #expect(PointSign.name(for: "фотопрогулка") == "park")
        #expect(PointSign.name(for: "Аквапарк") == "park")
        #expect(PointSign.name(for: "горнолыжный") == "ski")
    }
}
