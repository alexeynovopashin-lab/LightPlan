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
        guard snapshot.sessions.contains(where: { $0.id == id }) else { return }
        cardId = id
    }

    public func closeCard() { cardId = nil }

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
