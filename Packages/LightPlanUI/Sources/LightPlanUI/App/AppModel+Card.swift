import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

// MARK: - Карточка события (итерация 25)

extension AppModel {

    /// Открытая карточка (веб `openCard`); запись ушла в корзину или
    /// стёрта — карточки нет.
    public var card: Session? {
        guard let id = cardId else { return nil }
        return snapshot.sessions.first { $0.id == id }
    }

    public func openCard(id: String) {
        guard let s = snapshot.sessions.first(where: { $0.id == id }) else { return }
        if cardId != id { cardFolds = []; cardTuning = false; cardDocMessage = nil }
        cardId = id
        askCardWeather(s)
        Task { await learnZone(of: s) }
    }

    /// Пояс точки съёмки у геокодера (шаг 3 итерации 25). Без него пояс —
    /// оценка по долготе: Томск выходит +6 вместо +7, и фаза, «Завершить»,
    /// часы плитки и студийный час шли на час позже. Узнанный пояс ложится в
    /// кэш места и в снимок (ключ веба `zones`) — офлайн на съёмке он уже есть.
    func learnZone(of s: Session) async {
        guard let p = Stops.skyPoint(of: s, spots: snapshot.spots, studios: snapshot.studios),
              await place.learnZone(at: GeoCoordinate(latitude: p.latitude, longitude: p.longitude))
        else { return }
        snapshot.extra["zones"] = .object(place.zones.entries.mapValues { .string($0) })
        persist()
    }

    public func closeCard() {
        if let id = cardId, let s = snapshot.sessions.first(where: { $0.id == id }) { acknowledgeForecast(s) }
        cardId = nil
        cardFolds = []
        cardDocMessage = nil
        cardTuning = false
    }

    /// Настенные часы места съёмки сейчас (веб `nowAt(shootAt(s))`): в поездке
    /// они расходятся с часами телефона. Запись без точки живёт по поясу места
    /// приложения — как её момент у наложений (`Moment.of`).
    func wallNow(at s: Session) -> WallTime {
        let off: Double
        if let p = Stops.skyPoint(of: s, spots: snapshot.spots, studios: snapshot.studios) {
            off = place.zones.utcOffsetHours(latitude: p.latitude, longitude: p.longitude, on: today)
        } else {
            off = Double(TimeZone(identifier: place.zone.identifier)?.secondsFromGMT(for: now()) ?? 0) / 3600
        }
        return WallTime(moment: Moment(now()), utcOffsetHours: off)
    }

    /// Минута шкалы съёмки сейчас по часам места (веб `nowMinOf`); `nil` — не
    /// в сутки съёмки.
    func nowMinute(of s: Session) -> Int? { s.minute(at: wallNow(at: s)) }

    /// Секунды текущей минуты: у всех поясов они одни и те же.
    var nowSecond: Int { Int(((nowMs / 1000) % 60 + 60) % 60) }

    /// Метка пояса места у часов плитки (веб `tzTag`): «UTC+3», если пояс
    /// места расходится с поясом телефона; иначе и у записи без точки — `nil`.
    func zoneTag(of s: Session) -> String? {
        guard let p = Stops.skyPoint(of: s, spots: snapshot.spots, studios: snapshot.studios) else { return nil }
        let there = place.zones.utcOffsetHours(latitude: p.latitude, longitude: p.longitude, on: today)
        let here = Double(deviceZone.secondsFromGMT(for: now())) / 3600
        return abs(here - there) < 0.01 ? nil : BlockSheet.tzText(there)
    }

    /// Фаза записи сейчас (веб `eventPhase`) — с настройкой «Завершать вручную».
    public func phase(of s: Session) -> EventPhase {
        EventPhase.of(s, now: wallNow(at: s), manualEnd: settings.manualEnd)
    }

    /// Кнопка «Завершить» (веб `#cdFinRow`): ручной режим, съёмка идёт.
    /// Встречу и событие кнопкой не завершают (`notWork`). «Сегодня» веба
    /// (`nowMinOf`) отдельно не проверяется: «во время» без минуты шкалы не
    /// бывает.
    public func canFinish(_ s: Session) -> Bool {
        settings.manualEnd && s.kind == .shoot && phase(of: s) == .during
    }

    /// «Завершить»: отметка — минута шкалы съёмки по часам места, та же, с
    /// которой сравнивает фаза. Веб пишет часы телефона и в чужом поясе
    /// держит съёмку идущей лишние часы — ошибку не переносим (шаг 2 25).
    public func finishSession(id: String) {
        guard let i = snapshot.sessions.firstIndex(where: { $0.id == id }),
              canFinish(snapshot.sessions[i]),
              let m = snapshot.sessions[i].minute(at: wallNow(at: snapshot.sessions[i])) else { return }
        snapshot.sessions[i].doneAt = m
        snapshot.sessions[i].modifiedAt = nowMs
        persist()
    }

    /// Выключили ручной режим — отметки снимаются со всех записей (веб
    /// `sessions.forEach(delete s.doneAt)`): иначе завершённая руками съёмка
    /// осталась бы завершённой без кнопки.
    func clearFinishMarks() {
        let ms = nowMs
        for i in snapshot.sessions.indices where snapshot.sessions[i].doneAt != nil {
            snapshot.sessions[i].doneAt = nil
            snapshot.sessions[i].modifiedAt = ms
        }
    }
}
