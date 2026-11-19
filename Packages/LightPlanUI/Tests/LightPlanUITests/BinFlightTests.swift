import CryptoKit
import Foundation
import Testing
@testable import LightPlanUI
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Полёт в корзину (29.7): звук — записанный `TRASH_B64` и громкость `trashSound` (сверка с живой бетой через
/// `Tools/sound_ref.js`), порядок и интервалы фаз — `deleteToBin` беты, `Reduce Motion` без звука.
/// Серийно: журнал фаз и ответ на «Уменьшить движение» — общие на процесс.
@MainActor
@Suite(.serialized)
struct BinFlightTests {

    private struct Ref: Decodable {
        let trashSha256: String
        let trashBytes: Int
        let trashGain: Double
    }

    private static let ref: Ref = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "sound_ref.json")
        return try! JSONDecoder().decode(Ref.self, from: Data(contentsOf: url))
    }()

    private static func resource(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/LightPlanUI/Resources/Sound/\(name).wav")
        return try! Data(contentsOf: url)
    }

    @Test func trashWavIsByteForByteTheBetaSample() {
        let data = Self.resource("trash")
        #expect(data.count == Self.ref.trashBytes)
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(hex == Self.ref.trashSha256)
    }

    @Test func trashGainIsTheBetas() {
        #expect(SoundCue.trash.gain == Self.ref.trashGain)
        #expect(Self.ref.trashGain == 0.165)
    }

    /// Числа `deleteToBin` и стилей беты: пауза 0,2, глоток на 0,43 полёта, уезд +0,32, скрыт +0,34.
    @Test func timelineIsTheBetas() {
        #expect(BinTimeline.size == 56)
        #expect(BinTimeline.offscreen == 120)
        #expect(BinTimeline.rise == 0.34)
        #expect(BinTimeline.pause == 0.2)
        #expect(BinTimeline.flight == 0.42)
        #expect(BinTimeline.flightScale == 0.05)
        #expect(abs(BinTimeline.gulpAtTotal - 0.63) < 1e-9)
        #expect(BinTimeline.gulp == 0.3 && BinTimeline.gulpPeak == 1.16 && BinTimeline.gulpPeakAt == 0.4)
        #expect(abs(BinTimeline.leaveAtTotal - 0.95) < 1e-9)
        #expect(abs(BinTimeline.hideAtTotal - 1.29) < 1e-9)
        // `bottom: tabh + 26`, `--tabh` 84 (замер беты на 430×932).
        #expect(BinTimeline.lift == 110)
        #expect(BinTimeline.lift == TabBarView.height + 26)
    }

    private static func withSound<T>(_ on: Bool, _ body: () async throws -> T) async rethrows -> T {
        let was = UserDefaults.standard.object(forKey: SoundCenter.enabledKey)
        defer { UserDefaults.standard.set(was, forKey: SoundCenter.enabledKey) }
        UserDefaults.standard.set(on, forKey: SoundCenter.enabledKey)
        return try await body()
    }

    private static func trashPlays(since n: Int) -> [SoundPlay] {
        Array(SoundCenter.journal.dropFirst(n)).filter { $0.cue == .trash }
    }

    /// Ручные часы полёта (31.10): время стоит, пока тест не переведёт его к метке, на которой спит полёт. Раньше тест
    /// мерил настоящие секунды между строками журнала, и под нагрузкой полного прогона главный поток отрабатывал метку
    /// на 50–250 мс позже (замер 19.11: «rise → fly» 0,04 и 0,25 вместо 0,2; «hide» не успевал за 1,5 с), а пропавшая
    /// фаза роняла весь процесс тестов выходом за край массива.
    @MainActor
    final class StepClock {
        private(set) var now = 100.0
        private var sleeper: (at: Double, wake: CheckedContinuation<Void, Never>)?
        var clock: BinClock {
            BinClock(now: { [unowned self] in now }, wait: { [unowned self] t in
                guard t > now else { return }
                await withCheckedContinuation { sleeper = (t, $0) }
            })
        }
        /// Ждать, пока полёт уснёт до метки или `done()`. Настоящие секунды — только страховка от зависания (30 с), не
        /// замер: исход не зависит от того, сколько их прошло. `false` — так и не дождались.
        func settle(or done: @MainActor () -> Bool) async -> Bool {
            let guardUntil = ContinuousClock.now + .seconds(30)
            while sleeper == nil && !done() {
                if ContinuousClock.now > guardUntil { return false }
                // Сон, а не `yield`: пустой круг на главном потоке не даёт обернуться циклу событий и душит соседние тесты.
                try? await Task.sleep(for: .milliseconds(2))
            }
            return true
        }
        /// Перевести часы на метку спящего и разбудить его.
        func advance() {
            guard let s = sleeper else { return }
            sleeper = nil
            now = s.at
            s.wake.resume()
        }
    }

    /// Порядок и паузы полёта — по ручным часам: фаза отмечается в момент, на который её поставило расписание, и так же
    /// под любой нагрузкой. Строки журнала берутся только этого полёта (журнал общий на процесс).
    @Test func oneDeletionIsOneSoundAndOnePhaseSequence() async throws {
        try await Self.withSound(true) {
            BinFlightControl.calm(false)
            defer { BinFlightControl.reset() }
            SoundCenter.prepare()
            let steps = StepClock()
            let flight = BinFlight()
            flight.clock = steps.clock
            let t0 = steps.now
            let before = SoundCenter.journal.count
            var commits = 0, commitAt = -1.0
            flight.fly(subjects: ["x"]) { commits += 1; commitAt = steps.now - t0 }
            #expect(commits == 0, "запись стирается в глоток, не сразу")
            // Фаза → момент ручных часов, когда она появилась в журнале.
            var at: [String: Double] = [:]
            var phases: [String] = []
            @MainActor func mine() -> [String] { BinLog.journal.filter { $0.flight == flight.id }.map(\.phase) }
            var stalled = false
            for _ in 0..<40 {
                guard await steps.settle(or: { mine().contains("hide") }) else { stalled = true; break }
                for p in mine() where at[p] == nil { at[p] = steps.now - t0; phases.append(p) }
                if phases.contains("hide") { break }
                if !phases.contains("gulp") { #expect(commits == 0, "до глотка запись цела: \(phases)") }
                steps.advance()
            }
            #expect(!stalled, "полёт не уснул и не кончился за 30 с: \(phases)")
            #expect(phases == ["rise", "fly", "gulp", "leave", "hide"], "\(phases)")
            try #require(phases.count == 5, "фаз \(phases.count): дальше сверять нечего")
            // Расписание беты (`deleteToBin`): полёт через 0,2; глоток на 0,43 полёта, но не раньше, чем анимация плашки
            // кончилась (добавка до 12 × 8 мс); уезд через 0,32 после глотка; скрыт ещё через 0,34.
            let fly = at["fly"]!, gulp = at["gulp"]!, leave = at["leave"]!, hide = at["hide"]!
            try? "fly=\(fly) gulp=\(gulp) leave=\(leave) hide=\(hide)\n".write(toFile: "/tmp/cc-bin-steps.txt", atomically: true, encoding: .utf8)
            #expect(at["rise"] == 0)
            #expect(abs(fly - 0.2) < 1e-9, "fly на \(fly)")
            #expect(gulp >= 0.63 - 1e-9 && gulp <= 0.63 + 12 * 0.008 + 1e-9, "gulp на \(gulp)")
            #expect(abs(leave - gulp - 0.32) < 1e-9, "leave на \(leave), глоток на \(gulp)")
            #expect(abs(hide - leave - 0.34) < 1e-9, "hide на \(hide), уезд на \(leave)")
            #expect(commits == 1)
            #expect(abs(commitAt - gulp) < 1e-9, "commit на \(commitAt), глоток на \(gulp)")
            // Одно смятие на стирание: этот полёт позвал звук один раз; в общем журнале звук именно беты.
            #expect(flight.sounds == 1)
            let plays = Self.trashPlays(since: before)
            #expect(!plays.isEmpty && plays.allSatisfy { $0.gain == 0.165 && $0.event == "binTrash" })
            #expect(!flight.shown && !flight.busy && flight.subjects.isEmpty)
        }
    }

    /// Настоящие часы полёта не будят раньше метки: под нагрузкой они могут только опоздать (31.10).
    @Test func liveClockNeverWakesBeforeTheMark() async {
        let c = BinClock.live
        for d in [0.0, 0.008, 0.05] {
            let mark = c.now() + d
            await c.sleep(until: mark)
            #expect(c.now() >= mark, "проснулись на \(mark - c.now()) с раньше метки")
        }
    }

    @Test func reduceMotionErasesAtOnceWithoutSound() async {
        await Self.withSound(true) {
            BinFlightControl.calm(true)
            defer { BinFlightControl.reset() }
            BinLog.reset()
            let flight = BinFlight()
            let before = SoundCenter.journal.count
            var commits = 0
            flight.fly(subjects: ["x"]) { commits += 1 }
            #expect(commits == 1)
            #expect(flight.sounds == 0)
            #expect(BinLog.journal.filter { $0.flight == flight.id }.map(\.phase) == ["calm"])
            #expect(!flight.shown)
        }
    }

    @Test func switchedOffClicksSilenceTheCrumple() async {
        await Self.withSound(false) {
            BinFlightControl.calm(false)
            defer { BinFlightControl.reset() }
            let flight = BinFlight()
            let before = SoundCenter.journal.count
            var commits = 0
            flight.fly { commits += 1 }
            try? await Task.sleep(for: .milliseconds(1400))
            #expect(commits == 1)
            #expect(Self.trashPlays(since: before).isEmpty)
        }
    }

    // MARK: - Что стирается, фиксируется при подтверждении

    private struct NoWeather: WeatherSource {
        func fetchHourly(at place: Place) async throws -> HourlyWeather {
            HourlyWeather(time: [], cloud: [], temperature: [], windSpeed: [], precipitation: [], weatherCode: [])
        }
        func fetchAir(at place: Place) async throws -> [CivilDate: [Int: AirSample]] { [:] }
    }
    private struct SilentGeocoder: ReverseGeocoding {
        func answer(for c: GeoCoordinate) async throws -> GeocodeAnswer {
            GeocodeAnswer(locality: nil, region: nil, country: nil, zoneIdentifier: nil)
        }
    }
    private struct NoCities: CityLookup {
        func cities(matching query: String) async throws -> [CityHit] { [] }
    }
    private final class NoLocator: DeviceLocating {
        var isAlreadyAuthorized: Bool { false }
        func currentFix() async -> DeviceFix { .unavailable }
    }

    private func moodModel() -> AppModel {
        func shot(_ id: String) -> JSONValue { .object(["id": .string(id), "k": .string("img"), "tags": .array([]), "im": .string(id)]) }
        func board(_ id: String, _ kind: String, _ items: [String], sid: String? = nil) -> JSONValue {
            var o: [String: JSONValue] = ["id": .string(id), "kind": .string(kind), "genre": .string("wedding"),
                                          "items": .array(items.map { .string($0) })]
            if let sid { o["sid"] = .string(sid) }
            return .object(o)
        }
        var snap = Snapshot()
        snap.sessions = [Session(id: "w", kind: .shoot, day: CivilDate(year: 2026, month: 10, day: 1), start: 600, end: 1380,
                                 duration: 780, genre: .wedding)]
        snap.extra["shots"] = .array(["a", "b", "c", "d"].map(shot))
        snap.extra["boards"] = .array([board("sh", "shoot", ["a", "b", "c", "d"], sid: "w"), board("tpl", "tpl", ["d"])])
        let now = ISO8601DateFormatter().date(from: "2026-09-30T09:00:00+03:00")!
        return AppModel(snapshot: snap, store: nil, language: "ru", zone: TimeZone(identifier: "Europe/Moscow")!,
                        locator: NoLocator(), geocoder: SilentGeocoder(), cityLookup: NoCities(),
                        weatherSource: NoWeather(), now: { now })
    }

    /// Ревью 29.7: выбор сменился, пока кадры летят в корзину, — стираются ровно подтверждённые.
    @Test func framesAreFixedAtConfirmationNotAtTheGulp() async {
        BinFlightControl.calm(false)
        defer { BinFlightControl.reset() }
        let app = moodModel()
        app.openMbFolder(boardId: "sh")
        app.toggleMbPicking(); app.toggleMbPick("a"); app.toggleMbPick("d")
        app.mbConfirmRemovePicked()
        // За время полёта человек снял «a» и «d» и отметил «b».
        app.toggleMbPick("a"); app.toggleMbPick("d"); app.toggleMbPick("b")
        #expect(app.mbLibrary().board("sh")?.items == ["a", "b", "c", "d"], "до глотка ничего не стёрто")
        try? await Task.sleep(for: .milliseconds(1500))
        let lib = app.mbLibrary()
        #expect(lib.board("sh")?.items == ["b", "c"], "\(lib.board("sh")?.items ?? [])")
        // Корзина мудборда съёмки (29б): «a» (нигде больше не лежит) и «d» (лежит ещё в жанре) — в корзине, «b» не тронут.
        #expect(Set(lib.board("sh")?.bin.map(\.id) ?? []) == ["a", "d"], "\(lib.board("sh")?.bin.map(\.id) ?? [])")
        #expect(lib.shot("a") != nil && lib.shot("d") != nil && lib.shot("b") != nil)
    }

    /// Хвост 29.7: отметил «a», «d» → подтвердил → пока летит, отметил «b» → после глотка из выбора ушли
    /// только стёртые, «b» остался отмеченным (раньше выбор обнулялся целиком).
    @Test func pickMadeDuringFlightSurvivesTheGulp() async {
        BinFlightControl.calm(false)
        defer { BinFlightControl.reset() }
        let app = moodModel()
        app.openMbFolder(boardId: "sh")
        app.toggleMbPicking(); app.toggleMbPick("a"); app.toggleMbPick("d")
        app.mbConfirmRemovePicked()
        app.toggleMbPick("b")
        try? await Task.sleep(for: .milliseconds(1500))
        #expect(app.mbLibrary().board("sh")?.items == ["b", "c"])
        #expect(app.mb.pick?.ids == ["b"], "выбор: \(app.mb.pick?.ids ?? [])")
    }

    /// Ничего не отмечали за полёт — выбор кончается, как раньше.
    @Test func pickEndsWhenNothingElseWasMarked() async {
        BinFlightControl.calm(false)
        defer { BinFlightControl.reset() }
        let app = moodModel()
        app.openMbFolder(boardId: "sh")
        app.toggleMbPicking(); app.toggleMbPick("a"); app.toggleMbPick("d")
        app.mbConfirmRemovePicked()
        try? await Task.sleep(for: .milliseconds(1500))
        #expect(app.mb.pick == nil)
    }
}
