#if DEBUG
import SwiftUI
import LightPlanCore

/// Прицел в центре кадра (шаг 29.8в.11): четыре чёрточки вокруг пустой середины — диск светила остаётся виден.
/// Белый штрих на тёмной обводке читается и на светлом небе, и на тёмном. Касаний не берёт.
struct SunARMeasureCrosshair: View {
    private static let gap: CGFloat = 7
    private static let arm: CGFloat = 20

    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let lines = Path { p in
                for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
                    p.move(to: CGPoint(x: c.x + dx * Self.gap, y: c.y + dy * Self.gap))
                    p.addLine(to: CGPoint(x: c.x + dx * (Self.gap + Self.arm), y: c.y + dy * (Self.gap + Self.arm)))
                }
            }
            ZStack {
                lines.stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                lines.stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Слова и числа плашки замера. Отдельно от вида, чтобы тесты читали ту же строку, что на экране.
struct MeasureText {
    let lexicon: Lexicon
    let language: String

    private var numbers: NumberText { NumberText(language: language) }

    /// «+4,2°» / «−0,8°»: знак всегда, минус настоящий; ноль после округления — без знака.
    func degrees(_ v: Double, signed: Bool = true) -> String {
        let rounded = (abs(v) * 10).rounded() / 10
        let body = numbers.num(rounded, digits: 1) + "°"
        guard signed, rounded != 0 else { return body }
        return (v < 0 ? "−" : "+") + body
    }

    /// «Отклонение: +4,2° по курсу, −0,8° по высоте, разброс 1,1°».
    func headline(_ r: MeasureResult) -> String {
        lexicon.t("ar.measureResult", ["az": degrees(r.motionAzimuth.median), "alt": degrees(r.altitude.median),
                                       "r": degrees(r.scatter, signed: false)])
    }

    /// Второй источник курса — системный компас; `nil`, когда он молчал.
    func compassLine(_ r: MeasureResult) -> String? {
        r.compassAzimuth.map {
            lexicon.t("ar.measureCompass", ["az": degrees($0.median), "r": degrees($0.range, signed: false)])
        }
    }

    /// «Точность компаса ±15° · системный компас · север истинный · поле: высокое».
    func accuracyLine(_ rec: MeasureRecord) -> String {
        let r = rec.result
        var parts: [String] = []
        if let a = r.headingAccuracy {
            parts.append(lexicon.t("ar.measureAccuracy", ["n": numbers.num(a.rounded(), digits: 0)]))
        } else {
            parts.append(lexicon.t("ar.measureAccuracyNone"))
        }
        if let north = rec.trueNorth { parts.append(lexicon.t(north ? "ar.measureNorthTrue" : "ar.measureNorthMagnetic")) }
        if let level = r.magneticLevel { parts.append(lexicon.t("ar.measureLevel\(level)")) }
        return parts.joined(separator: " · ")
    }

    func refusal(_ why: MeasureRefusal, body: MeasureBody) -> String {
        let moon = body == .moon
        switch why {
        case .belowHorizon: return lexicon.t(moon ? "ar.measureBelowMoon" : "ar.measureBelowSun")
        case .offAim: return lexicon.t(moon ? "ar.measureOffMoon" : "ar.measureOffSun")
        case .noData: return lexicon.t("ar.measureNoData")
        case .noSensor: return lexicon.t("ar.measureNoSensor")
        }
    }

    func bodyName(_ b: MeasureBody) -> String { lexicon.t(b == .sun ? "ar.measureSun" : "ar.measureMoon") }

    /// Строка истории: «14:05:12 ☀ +4,2° / −0,8° · 1,1° · силикон».
    func historyLine(_ rec: MeasureRecord) -> String {
        let r = rec.result
        let time = rec.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
        let mark = r.body == .sun ? "☀︎" : "☾"
        let label = rec.caseLabel.isEmpty ? "—" : rec.caseLabel
        return "\(time) \(mark) \(degrees(r.motionAzimuth.median)) / \(degrees(r.altitude.median)) · \(degrees(r.scatter, signed: false)) · \(label)"
    }
}

/// Плашка замера: идёт набор, итог или отказ; тело, метка чехла, «Поделиться» и история последних десяти.
struct SunARMeasurePlate: View {
    @Bindable var station: MeasureStation
    let lexicon: Lexicon
    let language: String

    private var text: MeasureText { MeasureText(lexicon: lexicon, language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) { status }
                Spacer(minLength: 4)
                Button { station.close() } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lexicon.t("ar.measureClose"))
            }
            if !station.isCollecting {
                controls
                if !station.history.isEmpty { history }
            }
        }
        .foregroundStyle(SunARInk.light)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(GlassPlate(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), opacity: SunARInk.plateOpacity))
        .environment(\.colorScheme, .dark)
        .shotNode("ar.measure", text: summary)
    }

    @ViewBuilder private var status: some View {
        switch station.state {
        case .idle:
            Text(lexicon.t("ar.measureHint")).font(.system(size: 13))
        case .collecting(let p):
            Text(lexicon.t("ar.measureCollecting", ["n": NumberText(language: language).num((p * 100).rounded(), digits: 0)]))
                .font(.system(size: 14, weight: .medium).monospacedDigit())
            ProgressView(value: p).tint(SunARInk.light).frame(maxWidth: 160)
        case .done(let rec):
            Text(text.headline(rec.result)).font(.system(size: 14, weight: .medium).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
            if let line = text.compassLine(rec.result) {
                Text(line).font(.system(size: 12).monospacedDigit()).opacity(0.85)
            }
            Text(text.accuracyLine(rec)).font(.system(size: 12).monospacedDigit()).opacity(0.85)
        case .refused(let why, let body):
            Text(text.refusal(why, body: body)).font(.system(size: 14, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(lexicon.t("ar.measureBody")).font(.system(size: 13)).opacity(0.85)
                ForEach(MeasureBody.allCases, id: \.self) { b in
                    Button { station.body = b } label: {
                        Text(text.bodyName(b)).font(.system(size: 13, weight: station.body == b ? .semibold : .regular))
                            .padding(.horizontal, 12).frame(minHeight: 32)
                            .background(Capsule().fill(Color.white.opacity(station.body == b ? 0.22 : 0.06)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(station.body == b ? [.isButton, .isSelected] : .isButton)
                }
                Spacer(minLength: 4)
                if station.logExists {
                    ShareLink(item: station.logURL) {
                        Text(lexicon.t("ar.measureShare")).font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12).frame(minHeight: 32)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                }
            }
            HStack(spacing: 6) {
                Text(lexicon.t("ar.measureCase")).font(.system(size: 13)).opacity(0.85)
                TextField("", text: $station.caseLabel, prompt: Text("…").foregroundStyle(SunARInk.light.opacity(0.5)))
                    .font(.system(size: 14)).textFieldStyle(.plain)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 10).frame(minHeight: 32)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lexicon.t("ar.measureHistory")).font(.system(size: 11, weight: .medium)).opacity(0.7)
            ForEach(Array(station.history.enumerated()), id: \.offset) { _, rec in
                Text(text.historyLine(rec)).font(.system(size: 11).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    /// Строка узла для снимков: что на плашке.
    private var summary: String {
        switch station.state {
        case .idle: return "idle"
        case .collecting(let p): return String(format: "collecting %.2f", p)
        case .done(let rec): return text.headline(rec.result)
        case .refused(let why, _): return "refused \(why.rawValue)"
        }
    }
}
#endif
