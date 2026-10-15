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

/// Шаг 29.11б. Колонны у «Томсон, зал Эдисон» ставило не слово «зал» (в словаре правил
/// такого корня нет), а постоянный знак `hall` на кнопке зала в форме. Здесь — оба конца:
/// слово «зал» не выбирает знак, и строка зала студии несёт знак студии.
struct PointSignHallWordTests {

    @Test func wordHallDoesNotPickTheRegistrySign() {
        for place in ["Томсон, зал Эдисон", "зал Эдисон", "Зал ожидания", "Большой зал", "Актовый зал",
                      "Мезал", "Салон «Зал»", "Hall Edison", "Lumen, hall White"] {
            #expect(PointSign.name(for: "", place: place) != "hall", "«\(place)» не ЗАГС")
            #expect(PointSign.name(for: "Фотостудия", place: place, studio: true) == "studio", "«\(place)»")
        }
        #expect(PointSign.name(for: "Фотостудия", place: "Томсон, зал Эдисон") == "studio")
    }

    @Test func registryWordsStillPickRegistrySign() {
        #expect(PointSign.name(for: "ЗАГС") == "hall")
        #expect(PointSign.name(for: "Выкуп") == "hall")
    }

    @Test func hallRowOfStudioStopCarriesStudioSign() {
        #expect(FormPlaceBlock.hallRowSign == "studio")
        #expect(IconLibrary.common[FormPlaceBlock.hallRowSign] != nil, "знак нарисован")
        #expect(FormPlaceBlock.hallRowSign != PointSign.name(for: "ЗАГС"), "не знак ЗАГСа")
    }
}
