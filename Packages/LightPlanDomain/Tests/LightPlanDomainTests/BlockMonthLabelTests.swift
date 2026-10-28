import Testing
@testable import LightPlanDomain

/// Подпись занятости в клетке месяца: первое слово заметки, без заметки — слово вида (Алексей 28.10).
@Suite struct BlockMonthLabelTests {
    private func t(_ note: String, _ lang: String = "ru") -> String { BlockMonthLabel.text(note: note, kindWord: "Дорога", language: lang) }

    @Test func firstWordOfTheNote() {
        #expect(BlockMonthLabel.text(note: "Дорога в Москву", kindWord: "Занято", language: "ru") == "Дорога")
        #expect(BlockMonthLabel.text(note: "Печать альбомов", kindWord: "Занято", language: "ru") == "Печать")
        #expect(BlockMonthLabel.text(note: "On the road to Paris", kindWord: "Busy", language: "en") == "On")
        #expect(BlockMonthLabel.text(note: "Día libre en casa", kindWord: "Ocupado", language: "es") == "Día")
    }

    @Test func shortAndPunctuationWordsAreSkipped() {
        #expect(t("  — встреча") == "встреча")
        #expect(t("в Москву") == "Москву")
        #expect(t("«Печать», альбомов") == "Печать")
        #expect(t("Дорога, дальше") == "Дорога")
    }

    @Test func oneWordEmptyAndNothingUsable() {
        #expect(t("Печать") == "Печать")
        #expect(t("") == "Дорога")
        #expect(t("   ") == "Дорога")
        #expect(t("— в") == "Дорога")          // нет слова длиннее знака: слово вида
    }

    @Test func noSpaceLanguagesKeepTheNote() {
        #expect(t("東京への移動", "ja") == "東京への移動")
        #expect(t("  去上海出差 ", "zh-Hans") == "去上海出差")
        #expect(BlockMonthLabel.splitsWords(language: "ru") && BlockMonthLabel.splitsWords(language: "en-US") && BlockMonthLabel.splitsWords(language: "es"))
        #expect(!BlockMonthLabel.splitsWords(language: "ja") && !BlockMonthLabel.splitsWords(language: "zh-Hans"))
    }
}
