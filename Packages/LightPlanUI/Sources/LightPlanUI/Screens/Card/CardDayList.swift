import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Что плитка дня рисует под строками «что сейчас» (29.11в). Лента — это нить с точками на ней; когда
/// на ленту нечего нанизать (одна точка, и «Золотого» рядом нет), нить не нужна, а круг одной точки
/// посреди пустой ленты читается как ошибка. Тогда точки идут строками списка.
enum DayTilePoints: Equatable {
    /// Две и больше точек на нити: прежняя лента, вид не менялся.
    case lane([RoutePoint])
    /// Меньше двух: строки — знак, имя, час справа, под именем место.
    case list([RoutePoint])
    /// Точек нет: под строками ничего.
    case none

    /// `golden` — минута «Золотого» (`laneGolden`): он тоже точка на нити, с ним и одна своя точка — лента.
    static func of(_ s: Session, golden: Int?) -> DayTilePoints {
        let timed = s.kind == .shoot ? s.timedRoute : []   // как `DayTileText.route(of:)`, без главного актора
        if timed.count + (golden == nil ? 0 : 1) >= 2 { return .lane(timed) }
        // Точка без часа в ленту не попадает (ей нечего показать на нити), а в списке стоит: после точек с часом.
        let rows = timed + (s.kind == .shoot ? s.route.filter { $0.start == nil && !$0.name.isEmpty } : [])
        return rows.isEmpty ? .none : .list(rows)
    }
}

/// Слова одной строки списка — отдельно от вида, чтобы тесты читали их словами.
struct DayRowText: Equatable {
    var name: String
    /// Час начала, «12:00»; у точки без часа — нет.
    var time: String?
    /// «Томсон, зал Эдисон»: место строкой, а если его нет — имя сохранённого места, затем студия с залом
    /// (слова карточки `studioSpotName`); пусто — строки нет.
    var place: String

    @MainActor
    init(_ r: RoutePoint, app: AppModel, f: PlannerFacts) {
        name = r.name
        time = r.start.map { f.fmt(Double($0)) }
        if !r.placeText.isEmpty { place = r.placeText }
        else if let sp = app.spots.first(where: { $0.id == r.spotId })?.name, !sp.isEmpty { place = sp }
        else { place = app.studioSpotName(r.studioId, hallId: r.hallId) }
    }
}

/// Список точек дня под плиткой, когда ленты нет (29.11в): знак точки (тот же, что на ленте — со знаком
/// студии у точки в студии), имя, час справа, под именем место до двух строк. Между строками — щель.
struct CardDayList: View {
    let app: AppModel
    let s: Session
    let rows: [RoutePoint]
    let phase: EventPhase
    let pal: Palette

    var body: some View {
        let nowMin = app.nowMinute(of: s)
        let f = PlannerFacts(app: app, dark: pal.dark)
        // Текущая — последняя начатая, только «во время» (как на ленте).
        let cur = phase == .during ? DayTileText.current(rows, nowMin) : -1
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                // Щель, не линия: сквозь неё виден фон страницы (`pal.surface`, как у черты даты).
                Rectangle().fill(pal.surface).frame(height: 1)
                row(rows[i], DayRowText(rows[i], app: app, f: f), now: i == cur, past: i != cur && past(rows[i], nowMin))
                    .shotNode("card.dayRow.\(i)", text: rows[i].name)
            }
        }
        .shotNode("card.dayList", text: "\(rows.count)")
    }

    private func past(_ r: RoutePoint, _ nowMin: Int?) -> Bool {
        if phase == .after { return true }
        guard let nowMin, let t = r.start else { return false }
        return t <= nowMin
    }

    private func row(_ r: RoutePoint, _ x: DayRowText, now: Bool, past: Bool) -> some View {
        let studio = app.studios.contains { $0.id == r.studioId }
        // Знак выбирается по тому же месту, что на ленте (строка точки или сохранённое место), не по подписи под именем.
        let signPlace = r.placeText.isEmpty ? (app.spots.first { $0.id == r.spotId }?.name ?? "") : r.placeText
        return HStack(alignment: .top, spacing: 10) {
            Icon(point: r.name, place: signPlace, studio: studio, size: 20, line: 1.4)
                .foregroundStyle(now ? pal.ink : past ? pal.brass : pal.ink5b)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(now ? pal.green : .clear, lineWidth: 1.4))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Имя переносится целиком: длинное не режется многоточием.
                    Text(r.name).font(webFont(14)).foregroundStyle(pal.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let t = x.time {
                        Text(t).font(webFont(12.5)).monospacedDigit().foregroundStyle(now ? pal.ink : pal.ink3)
                    }
                }
                if !x.place.isEmpty {
                    Text(x.place).font(webFont(12)).foregroundStyle(pal.ink4).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 3)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
