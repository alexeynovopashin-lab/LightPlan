import Foundation
import LightPlanCore
import LightPlanDomain

// MARK: - Референсы и документы в карточке (итерация 27, шаг 3)

/// Блок «Референсы»: заголовок и подзаголовок строки (полоски миниатюр нет —
/// решение Алексея 29.09; у веба её тело не видно, ошибка 20).
struct CardRefsRow: Equatable {
    var title: String
    var sub: String
    var count: Int
}

/// Что вышло из тапа по документу.
enum CardDocOpen: Equatable {
    /// Открыть адрес в браузере.
    case url(URL)
    /// Файл без облака, адрес не собрался — сообщение в самой карточке.
    case failed
    /// Нет ни файла, ни адреса — ничего.
    case none
}

private extension JSONValue {
    var stringValue: String? { if case .string(let v) = self { v } else { nil } }
}

extension AppModel {

    /// Кадры и подборки из снимка: `shots` и `boards` лежат в `extra` как есть.
    func refFrames() -> [RefFrame] {
        guard case .array(let a)? = snapshot.extra["shots"] else { return [] }
        return a.compactMap { v -> RefFrame? in
            guard case .object(let o) = v else { return nil }
            let im = o["im"]?.stringValue
            guard let id = o["id"]?.stringValue ?? im else { return nil }
            var tags: [String] = []
            if case .array(let t)? = o["tags"] { tags = t.compactMap(\.stringValue) }
            var w: Double?, h: Double?
            if case .number(let n)? = o["w"] { w = n }
            if case .number(let n)? = o["h"] { h = n }
            return RefFrame(id: id, kind: RefFrame.Kind(rawValue: o["k"]?.stringValue ?? "img") ?? .img,
                            im: im, path: o["path"]?.stringValue, url: o["url"]?.stringValue, tags: tags, w: w, h: h)
        }
    }

    func refBoards() -> [RefBoard] {
        guard case .array(let a)? = snapshot.extra["boards"] else { return [] }
        return a.compactMap { v -> RefBoard? in
            guard case .object(let o) = v, let k = RefBoard.Kind(rawValue: o["kind"]?.stringValue ?? "") else { return nil }
            var items: [String] = []
            if case .array(let t)? = o["items"] { items = t.compactMap(\.stringValue) }
            return RefBoard(kind: k, sid: o["sid"]?.stringValue, genre: o["genre"]?.stringValue, items: items)
        }
    }

    /// Кадры карточки: свои, потом набор жанра (веб `allRefs`).
    func cardRefs(_ s: Session) -> [RefFrame] {
        RefSet.compose(sessionId: s.id, genre: s.genre?.rawValue, shots: refFrames(), boards: refBoards())
    }

    /// Строка блока (веб `renderRefFold`): «Референсы» или «Референсы: Банкет»
    /// при текущей точке; «N кадров · набор жанра и съёмки». Состояние «на
    /// устройстве» не пишем: картинок на устройстве нет.
    func cardRefsRow(_ s: Session) -> CardRefsRow? {
        let frames = cardRefs(s)
        guard !frames.isEmpty else { return nil }
        var title = lexicon.t("card.refs")
        let route = s.timedRoute
        if let now = nowMinute(of: s) {
            let i = DayTileText.current(route, now)
            if i >= 0 { title = lexicon.t("card.refsAt", ["stage": route[i].name]) }
        }
        return CardRefsRow(title: title,
                           sub: lexicon.count("unit.frame", frames.count) + " · " + lexicon.t("card.refsFrom"),
                           count: frames.count)
    }

    /// Тап по документу (веб `openDoc`): ссылка — в браузер; файл с путём —
    /// облака в нативе нет до 30, значит сообщение, но в самой карточке (ошибка
    /// веба 22: там оно пишется в узел формы); без пути и адреса — ничего.
    @discardableResult
    func openCardDoc(_ d: Attachment) -> CardDocOpen {
        cardDocMessage = nil
        if d.source == .link, let u = d.url, let url = URL(string: u), url.scheme != nil { return .url(url) }
        if d.path != nil { cardDocMessage = lexicon.t("doc.openFail"); return .failed }
        return .none
    }
}

// MARK: - Полный экран референсов (итерация 27, шаг 4)

/// Состояние экрана: открытая съёмка, папка, просмотрщик. Кадры просмотрщика —
/// id в том порядке, что на экране на миг открытия (свои, набор, с фильтром).
struct RefsFullState: Equatable {
    var sessionId: String
    var tag: String?
    var viewerIds: [String] = []
    var pager: RefPager?
}

/// Что вышло из тапа по плитке.
enum RefTileOpen: Equatable {
    case viewer
    case url(URL)
    case none
}

extension AppModel {

    func openRefsFull(_ s: Session) {
        guard !cardRefs(s).isEmpty else { return }
        refsFull = RefsFullState(sessionId: s.id)
    }

    func closeRefsFull() { refsFull = nil }

    func setRefFolder(_ tag: String?) {
        guard refsFull != nil else { return }
        refsFull?.tag = tag
    }

    func refSections(_ s: Session) -> RefSections {
        RefSections(frames: cardRefs(s), tag: refsFull?.tag)
    }

    /// Тап по плитке (веб `openRefAt`): картинка — в просмотрщик, ссылка — в
    /// браузер, кадр без байтов и пути не открывается.
    @discardableResult
    func openRefFrame(_ id: String, in s: Session) -> RefTileOpen {
        let sec = refSections(s)
        guard let f = sec.flat.first(where: { $0.id == id }) else { return .none }
        if f.kind == .link, let u = f.url, let url = URL(string: u), url.scheme != nil { return .url(url) }
        let list = sec.viewable
        guard let at = list.firstIndex(where: { $0.id == id }) else { return .none }
        refsFull?.viewerIds = list.map(\.id)
        refsFull?.pager = RefPager(count: list.count, start: at)
        return .viewer
    }

    /// Кадр, на котором остановился просмотрщик.
    var refViewerFrameId: String? {
        guard let st = refsFull, let p = st.pager, st.viewerIds.indices.contains(p.index) else { return nil }
        return st.viewerIds[p.index]
    }

    /// Жест целого кадра по сдвигу кадра; `true` — кадр сменился.
    @discardableResult
    func refViewerSwipe(dx: Double, dy: Double) -> RefPager.Swipe {
        let d = RefPager.decide(dx: dx, dy: dy)
        _ = refsFull?.pager?.apply(d)
        return d
    }

    /// Просмотрщик закрыт; ответ — кадр, в чью плитку он летит (тот, на котором
    /// остановились, а не с которого открывали: ошибка веба 21).
    @discardableResult
    func closeRefViewer() -> String? {
        let home = refViewerFrameId
        refsFull?.pager = nil
        refsFull?.viewerIds = []
        return home
    }

    /// Строка под заголовком: «Имя клиента · Банкет» (текущая точка, если есть).
    func refsFullSub(_ s: Session) -> String {
        var parts: [String] = []
        let name = PlannerWords(lexicon: lexicon, orgs: orgs).clientName(s)
        if !name.isEmpty { parts.append(name) }
        let route = s.timedRoute
        if let now = nowMinute(of: s) {
            let i = DayTileText.current(route, now)
            if i >= 0 { parts.append(route[i].name) }
        }
        return parts.joined(separator: " · ")
    }
}
