import Foundation
import Testing
import LightPlanCore
import LightPlanDomain

/// Шаг «Поле-1» (правки с первой съёмки в поле, слова Алексея 25.10): гости, подвиды, звёздочки мессенджеров.
/// Слова подвидов и глава «Плейлисты» — в тестах интерфейса (`FieldOneWordsTests`, `SettingsChaptersTests`).
@Suite struct FieldOneTests {
    let day = CivilDate(year: 2026, month: 10, day: 25)

    func party() -> EventForm {
        EventForm.new(id: "p1", day: day, start: 840, fromLight: false, mode: .shoot, genre: .party, prefs: nil,
                      light: FormLightWindow(start: 1178, end: 1230))
    }

    // MARK: 1. Гости

    @Test func plusCountsByOneBelowTenAndByTenFromTen() {
        var n = 0
        var seen: [Int] = []
        for _ in 0..<13 { n = Guests.more(n); seen.append(n) }
        #expect(seen == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40])
    }

    @Test func minusGoesFromTenDownToOneThenToTheDash() {
        var n = 30
        var seen: [Int] = []
        for _ in 0..<12 { n = Guests.fewer(n); seen.append(n) }
        #expect(seen == [20, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0], "10 → 9 → … → 1 → «—», как просил Алексей")
        #expect(Guests.fewer(0) == 0, "ниже «—» не уходит")
    }

    @Test func aNumberBetweenTensNeverStepsOverTen() {
        #expect(Guests.fewer(15) == 10, "15 идёт в 10, а не в 5")
        #expect(Guests.fewer(11) == 10)
        #expect(Guests.more(15) == 25, "вверх — на десяток, как у веба")
    }

    @Test func plusStopsAtTheCeiling() {
        #expect(Guests.more(1990) == 2000)
        #expect(Guests.more(1995) == 2000)
        #expect(Guests.more(2000) == 2000)
        #expect(Guests.fewer(2000) == 1990)
        #expect(Guests.more(-4) == 1, "отрицательного не бывает")
    }

    @Test func typedDigitsBecomeTheNumber() {
        #expect(Guests.parse("45") == 45)
        #expect(Guests.parse("1") == 1)
        #expect(Guests.parse("2000") == 2000)
    }

    @Test func zeroAndEmptyAndLettersAreNoGuests() {
        #expect(Guests.parse("0") == 0)
        #expect(Guests.parse("") == 0)
        #expect(Guests.parse("   ") == 0)
        #expect(Guests.parse("abc") == 0)
        #expect(Guests.parse("—") == 0, "служебное «—» тоже не число")
        #expect(Guests.parse("٣") == 0, "чужие цифры не принимаются: клавиатура даёт только 0–9")
        #expect(Guests.sanitize("0") == "0", "набранный ноль остаётся в поле, пока из него не вышли")
        #expect(Guests.sanitize("") == "")
    }

    @Test func overTheCeilingIsCutToTheCeiling() {
        #expect(Guests.parse("2001") == 2000)
        #expect(Guests.parse("2500") == 2000)
        #expect(Guests.parse("99999") == 2000, "пятая цифра отрезана, потом потолок — как в вебе")
        #expect(Guests.sanitize("2001") == "2000", "и поле показывает 2000, а не набранное")
    }

    @Test func pastedTextKeepsOnlyItsDigits() {
        #expect(Guests.parse("12 человек") == 12)
        #expect(Guests.sanitize("12 человек") == "12")
        #expect(Guests.parse("гостей: 7") == 7)
        #expect(Guests.parse("007") == 7)
        #expect(Guests.sanitize("007") == "7")
        #expect(Guests.parse("-5") == 5, "минус — не цифра, как в вебе")
    }

    @Test func aTypedZeroStaysInTheFieldWhileItIsEdited() {
        // Ревью GPT к 17542a4: был 5, набрали «0» — число стало 0, а поле не должно стереть набранное.
        #expect(Guests.editingText("0", value: 0) == "0")
        #expect(Guests.editingText("", value: 0) == "")
        #expect(Guests.editingText("5", value: 5) == "5", "набранное и есть число — не трогаем")
        #expect(Guests.editingText("007", value: 7) == "007")
        // Число ушло кнопкой — поле берёт его.
        #expect(Guests.editingText("5", value: 6) == "6")
        #expect(Guests.editingText("1", value: 0) == "", "«−» с единицы: в поле пусто, цифры пойдут с чистого места")
        #expect(Guests.editingText("20", value: 10) == "10")
    }

    @Test func theFormTakesTypingAndButtonsOneAfterAnother() {
        var f = party()
        f.typeGuests("7")
        #expect(f.guests == 7)
        f.fewerGuests()
        #expect(f.guests == 6, "после набранного 7 минус даёт 6")
        f.typeGuests("")
        #expect(f.guests == 0, "стёрли — снова «—»")
        f.moreGuests()
        #expect(f.guests == 1, "из «—» плюс даёт одного гостя, а не десять")
        f.typeGuests("12 человек")
        f.moreGuests()
        #expect(f.guests == 22)
        f.typeGuests("2001")
        #expect(f.guests == 2000)
    }

    @Test func sevenGuestsSurviveSaving() {
        var f = party()
        f.typeGuests("7")
        let s = f.session(orgName: nil, and: " и ")
        #expect(s.guests == 7)
        #expect(EventForm.editing(s).guests == 7)
    }

    // MARK: 2. Подвиды

    @Test func familyGetsABirthdayAndPartyGetsBachelorParties() {
        #expect(Genre.family.subGenres.contains(.birthday))
        #expect(Genre.party.subGenres.contains(.bachelorette) && Genre.party.subGenres.contains(.bachelor))
        #expect(Genre.party.subGenres.contains(.birthday), "в «Празднике» ДР остался")
    }

    @Test func theNewTilesStandLastSoTheOldOnesDoNotMove() {
        #expect(Genre.family.subGenres == [.baby, .pregnancy, .generations, .birthday])
        #expect(Genre.party.subGenres == [.birthday, .jubilee, .newyear, .graduation, .christening, .barmitzvah, .bachelorette, .bachelor])
    }

    @Test func aWrongGenreForgetsTheSubGenreOnlyForTheOnesThatDoNotOwnIt() {
        #expect(Genre.family.allows(.birthday) && Genre.party.allows(.birthday))
        #expect(!Genre.wedding.allows(.bachelorette) && !Genre.family.allows(.bachelor), "мальчишник не у «Семьи»")
        var f = party()
        f.pick(.party, sub: .bachelorette)
        #expect(f.subGenre == .bachelorette)
        f.pick(.family, sub: .bachelorette)
        #expect(f.subGenre == nil, "сменили жанр — чужое уточнение забыто")
        f.pick(.family, sub: .birthday)
        #expect(f.subGenre == .birthday, "а «День рождения» в «Семье» держится")
    }

    @Test func everySubGenreHasAnIconNameAndOnlyTheNewOnesAreOutsideTheWebTable() {
        #expect(SubGenre.nativeAdditions[.party] == [.bachelorette, .bachelor])
        #expect(SubGenre.nativeAdditions[.family] == [.birthday])
        #expect(Set(SubGenre.nativeAdditions.keys) == [.party, .family])
        for sub in SubGenre.allCases { #expect(!sub.iconName.isEmpty) }
    }

    @Test func aBachelorPartyShootRoundTripsThroughTheRecord() throws {
        var f = party()
        f.pick(.party, sub: .bachelorette)
        let s = f.session(orgName: nil, and: " и ")
        #expect(s.subGenre == .bachelorette)
        let json = try JSONEncoder().encode(s)
        let read = try JSONDecoder().decode(Session.self, from: json)
        #expect(read.subGenre == .bachelorette && read.genre == .party)
        let out = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        #expect(out["sub"] as? String == "bachelorette", "код пишется как есть — веб покажет его кодом")
    }

    @Test func aBirthdayInFamilyKeepsItsGenre() {
        var f = party()
        f.pick(.family, sub: .birthday)
        let s = f.session(orgName: nil, and: " и ")
        #expect(s.genre == .family && s.subGenre == .birthday)
    }

    // MARK: 3. Звёздочки мессенджеров

    static let ru = TelCountry.fallback

    static func person(_ tel: String = "", _ msg: [(MessengerKind, String)] = [], pref: MessengerKind? = nil) -> ClientPerson {
        var p = ClientPerson(name: "Алёна", phone: tel)
        p.messengers = msg.map { ClientMessenger(kind: $0.0.rawValue, value: $0.1) }
        p.preferred = pref?.rawValue
        return p
    }

    func stars(_ p: ClientPerson) -> [MessengerKind] { ClientReach.starred(in: p, country: Self.ru) }

    @Test func noStarsWithNoMessengerOrWithJustOne() {
        #expect(stars(Self.person("+79161234567")).isEmpty)
        #expect(stars(Self.person("+79161234567", [(.telegram, "olga")])).isEmpty, "один способ — выбирать не из чего")
        #expect(stars(Self.person("", [(.vk, "id123")])).isEmpty)
    }

    @Test func twoFilledMessengersBothGetAStar() {
        let p = Self.person("", [(.vk, "id123"), (.instagram, "olga")])
        #expect(stars(p) == [.vk, .instagram])
        let three = Self.person("", [(.vk, "id123"), (.instagram, "olga"), (.telegram, "olga_t")])
        #expect(stars(three) == [.vk, .instagram, .telegram])
    }

    @Test func anEmptyRowGetsNoStarEvenWhenOthersDo() {
        // Telegram без имени и без номера открыть нечем — звёздочки нет; ВК и Instagram с профилем — есть.
        let p = Self.person("", [(.vk, "id123"), (.telegram, ""), (.instagram, "olga")])
        #expect(stars(p) == [.vk, .instagram])
        // Пустое поле — второй способ, но не заполненный: звёздочек нет совсем.
        let one = Self.person("", [(.vk, "id123"), (.telegram, "")])
        #expect(stars(one).isEmpty)
    }

    @Test func aTelegramWithAnEmptyFieldCountsWhenThereIsARealPhone() {
        // По номеру Telegram и WhatsApp открываются без имени — это «заполненный» способ.
        let p = Self.person("+79161234567", [(.telegram, ""), (.whatsapp, "")])
        #expect(stars(p) == [.telegram, .whatsapp])
        let noTel = Self.person("", [(.telegram, ""), (.whatsapp, "")])
        #expect(stars(noTel).isEmpty)
    }

    @Test func aStarMovesTheWriteButtonAndTheLitStarAlike() {
        var p = Self.person("", [(.vk, "id123"), (.instagram, "olga")])
        #expect(ClientReach.primary(of: p, country: Self.ru)?.way == .messenger(.vk), "без звёздочки — первый вписанный")
        p.preferred = MessengerKind.instagram.rawValue
        #expect(ClientReach.primary(of: p, country: Self.ru)?.way == .messenger(.instagram))
        #expect(ClientReach.primary(of: p, country: Self.ru)?.url.absoluteString == "https://ig.me/m/olga")
        p.preferred = MessengerKind.vk.rawValue
        #expect(ClientReach.primary(of: p, country: Self.ru)?.url.absoluteString == "https://vk.me/id123", "и обратно")
    }

    @Test func aStarOnAnEmptyRowFallsBackToTheFirstFilledAndLightsThatOne() {
        // Старые данные: звезда стоит на строке без профиля. Горит должен тот, кого откроет кнопка.
        let p = Self.person("", [(.telegram, ""), (.vk, "id123"), (.instagram, "olga")], pref: .telegram)
        let lit = ClientReach.primary(of: p, country: Self.ru)?.way
        #expect(lit == .messenger(.vk))
        #expect(stars(p) == [.vk, .instagram], "звёздочки — у заполненных; пустого Telegram среди них нет")
    }

    @Test func removingTheStarredOneMovesTheStarToTheNextAndHidesItWhenOneIsLeft() {
        var p = Self.person("", [(.vk, "id123"), (.instagram, "olga")], pref: .instagram)
        ClientReach.removeMessenger(.instagram, from: &p)
        #expect(p.preferred == MessengerKind.vk.rawValue)
        #expect(stars(p).isEmpty, "остался один — звёздочки уходят")
        ClientReach.addMessenger(.telegram, to: &p)
        ClientReach.setMessenger(.telegram, "olga_t", in: &p)
        #expect(stars(p) == [.vk, .telegram], "вписали второй — звёздочки вернулись")
    }
}
