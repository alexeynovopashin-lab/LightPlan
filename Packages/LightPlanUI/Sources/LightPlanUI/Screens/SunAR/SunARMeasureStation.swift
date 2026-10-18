#if DEBUG
import SwiftUI
import LightPlanCore
import LightPlanData

/// Что измеритель отклонения помнит между замерами и входами: чем мерим, метка чехла и последние замеры (шаг 29.8в.11).
/// Флаги устройства, как «Луна» и «Млечный Путь»: в снимок съёмок и в облако не уходят.
@MainActor
protocol ARMeasureSettings: AnyObject {
    var body: MeasureBody { get set }
    var caseLabel: String { get set }
    var history: [MeasureRecord] { get set }
}

@MainActor
final class DeviceMeasureSettings: ARMeasureSettings {
    static let bodyKey = "lightplan.native.sunar.measure.body"
    static let caseKey = "lightplan.native.sunar.measure.case"
    static let historyKey = "lightplan.native.sunar.measure.history"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var body: MeasureBody {
        get { defaults.string(forKey: Self.bodyKey).flatMap(MeasureBody.init(rawValue:)) ?? .sun }
        set { defaults.set(newValue.rawValue, forKey: Self.bodyKey) }
    }
    var caseLabel: String {
        get { defaults.string(forKey: Self.caseKey) ?? "" }
        set { defaults.set(newValue, forKey: Self.caseKey) }
    }
    var history: [MeasureRecord] {
        get { defaults.data(forKey: Self.historyKey).flatMap { try? JSONDecoder().decode([MeasureRecord].self, from: $0) } ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.historyKey) }
    }
}

/// Замер на экране AR: собирает отсчёты из потока датчиков, показывает итог или отказ, пишет журнал (CSV) и историю.
///
/// Счёт — `SunARMeasurer` ядра; здесь только состояние плашки и файл. Отсчёты берутся из того же потока, что
/// рисует диск, а расчётное положение тела — по часам приложения и месту экрана (те же `SunTrack` / `MoonTrack`).
@MainActor @Observable
final class MeasureStation {
    enum State: Equatable {
        case idle
        /// Идёт набор: доля окна `0 … 1`.
        case collecting(Double)
        case done(MeasureRecord)
        case refused(MeasureRefusal, MeasureBody)
    }

    private(set) var state: State = .idle
    /// Плашка открыта (после первого нажатия «Замер», закрывается крестиком).
    private(set) var plateOpen = false
    var body: MeasureBody { didSet { settings.body = body } }
    var caseLabel: String { didSet { settings.caseLabel = caseLabel } }
    private(set) var history: [MeasureRecord]

    /// Куда пишется журнал: `-LPSunARMeasureLog <файл>` (имя без «/» — файл в `Documents` приложения), иначе
    /// `Documents/sunar_measure.csv`.
    let logURL: URL
    /// Журнал уже существует: «Поделиться» есть что отдавать.
    private(set) var logExists: Bool

    /// Окно набора не закрылось за это время: датчик замолчал.
    static let stallTimeout: Duration = .seconds(4)

    @ObservationIgnored private let settings: any ARMeasureSettings
    @ObservationIgnored private var measurer = SunARMeasurer()
    @ObservationIgnored private var context: Context?
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private let phone: String
    @ObservationIgnored private let system: String

    private struct Context {
        let body: MeasureBody
        let time: Date
        let moment: Date
        let placeSource: String
        let place: Place
        let trueNorth: Bool?
    }

    static var defaultLogURL: URL {
        let name = UserDefaults.standard.string(forKey: "LPSunARMeasureLog") ?? "sunar_measure.csv"
        return name.hasPrefix("/") ? URL(fileURLWithPath: name) : URL.documentsDirectory.appending(path: name)
    }

    init(settings: (any ARMeasureSettings)? = nil, logURL: URL? = nil, phone: String? = nil, system: String? = nil) {
        let s = settings ?? DeviceMeasureSettings()
        self.settings = s
        body = s.body
        caseLabel = s.caseLabel
        history = Array(s.history.prefix(Self.historyLimit))
        let url = logURL ?? Self.defaultLogURL
        self.logURL = url
        logExists = FileManager.default.fileExists(atPath: url.path)
        self.phone = phone ?? Self.phoneModel()
        self.system = system ?? Self.systemVersion()
    }

    static let historyLimit = 10

    // MARK: - Ход

    var isCollecting: Bool {
        if case .collecting = state { return true }
        return false
    }

    /// Нажатие «Замер»: набор начинается с первого же отсчёта потока. Без датчика (центр кадра ведёт палец) —
    /// отказ сразу: мерить нечем.
    func begin(place: Place, placeSource: String, moment: Moment, hasSensor: Bool, trueNorth: Bool?, now: Date = Date()) {
        epoch += 1
        plateOpen = true
        measurer = SunARMeasurer()
        guard hasSensor else {
            context = nil
            state = .refused(.noSensor, body)
            return
        }
        context = Context(body: body, time: now, moment: moment.date, placeSource: placeSource, place: place, trueNorth: trueNorth)
        state = .collecting(0)
        let mine = epoch
        Task { [weak self] in
            try? await Task.sleep(for: Self.stallTimeout)
            guard let self, self.epoch == mine, self.isCollecting else { return }
            self.stop(with: .noData)
        }
    }

    /// Отсчёт потока датчиков. Вне замера — ничего не делает.
    func take(_ s: AttitudeSample, moment: Moment, place: Place) {
        guard let context, isCollecting else { return }
        let aim = s.basis.aim
        let expected = context.body.expected(at: moment, in: place)
        // Место могло смениться, пока шёл набор (телефон ответил позже): считаем для нового, момент тот же.
        measurer.add(MeasureSample(time: s.time, aim: aim, compassHeading: s.trueHeading, expected: expected,
                                   headingAccuracy: s.headingAccuracy, magneticLevel: s.magneticAccuracy))
        state = .collecting(measurer.progress)
        if measurer.isComplete { finish(context, place: place) }
    }

    /// Экран закрыт или нажали крестик: набор бросается, плашка закрывается.
    func close() {
        epoch += 1
        context = nil
        plateOpen = false
        if isCollecting { state = .idle }
    }

    private func stop(with refusal: MeasureRefusal) {
        let b = context?.body ?? body
        context = nil
        state = .refused(refusal, b)
    }

    private func finish(_ c: Context, place: Place) {
        context = nil
        epoch += 1
        switch measurer.finish(body: c.body) {
        case .refused(let why):
            state = .refused(why, c.body)
        case .result(let r):
            let record = MeasureRecord(time: c.time, moment: c.moment, placeSource: c.placeSource,
                                       latitude: place.latitude, longitude: place.longitude, trueNorth: c.trueNorth,
                                       caseLabel: caseLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                                       phone: phone, systemVersion: system, result: r)
            history = Array(([record] + history).prefix(Self.historyLimit))
            settings.history = history
            append(record)
            state = .done(record)
        }
    }

    // MARK: - Журнал

    /// Одна строка на замер; заголовок — в новом файле.
    private func append(_ record: MeasureRecord) {
        let fm = FileManager.default
        var text = ""
        if !fm.fileExists(atPath: logURL.path) { text += MeasureCSV.header + "\n" }
        text += MeasureCSV.row(record) + "\n"
        guard let data = text.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: logURL)
        }
        logExists = fm.fileExists(atPath: logURL.path)
    }

    // MARK: - Устройство

    /// `iPhone16,2` — модель телефона; в симуляторе — модель, которую он изображает.
    static func phoneModel() -> String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static func systemVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
#endif
