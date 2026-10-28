import Foundation
import LightPlanCore

/// Когда экран активности есть и что с ним делать (30б.3, слова Алексея 25.10 и 26.10).
///
/// Запустить активность можно только при открытом приложении (замер 30б.3а: из фона запрос не проходит, а платного Push, который
/// запускает её удалённо, на бесплатной команде нет), поэтому всё решается в миг, когда приложение что-то узнало: запуск, возврат
/// на экран, запись данных, нажатие на уведомление «Студийный час». Правило — чистая функция от того, что идёт, и того, что уже
/// показано.
public enum ActivityRules {

    /// Сколько система держит активность — 8 часов (документация Apple, не мерено; ещё до 4 часов она остаётся на экране после конца).
    public static let systemLimit: TimeInterval = 8 * 3600

    /// Раньше этого возраста активность не перезапускается: двойное «вернулись на экран» подряд не должно мигать плашкой.
    public static let minRestartAge: TimeInterval = 60

    /// Что показано сейчас: съёмка и когда активность запрошена (в её свойствах).
    public struct Run: Equatable, Sendable {
        public var shootId: String
        public var startedAt: Date

        public init(shootId: String, startedAt: Date) {
            self.shootId = shootId
            self.startedAt = startedAt
        }
    }

    /// Почему сверяемся: приложение вернулось на экран (тут длинный день продлевается) или поменялись данные / нажали уведомление.
    public enum Reason: Sendable { case foreground, change }

    public enum Action: Equatable, Sendable {
        case none
        /// Запросить новую активность.
        case start
        /// Обновить кадр, активность остаётся.
        case update
        /// Закрыть и запросить заново: другая съёмка или продление длинного дня.
        case restart
        /// Закрыть: съёмки, которой нужна плашка, нет.
        case end
    }

    /// Съёмка, которой нужна плашка: идёт сейчас (началась, не кончилась; незакрытая вручную идёт, пока не нажмут «Завершить»),
    /// кроме той, что человек убрал с экрана блокировки сам.
    ///
    /// «Идёт» — как у виджета (`WidgetFrame.live`): одним определением на виджет и экран активности. Начало — само начало съёмки,
    /// без форы (слова Алексея: «когда съёмка началась»); запас до начала — вопрос Алексею, не решение исполнителя.
    public static func wanted(in feed: WidgetFeed, at now: Date, dismissed: Set<String> = []) -> WidgetFeed.Shoot? {
        let frame = feed.frame(at: now)
        guard frame.kind == .live, let shoot = frame.primary?.shoot, !dismissed.contains(shoot.id) else { return nil }
        return shoot
    }

    /// День длиннее срока системы: активность дожить до конца сама не может, её продлевают перезапуском (слово Алексея 25.10:
    /// «Продлевать»). Незакрытая вручную съёмка конца не знает — считаем её длинной по записанному концу, а после него — тоже.
    public static func isLongDay(_ s: WidgetFeed.Shoot, at now: Date) -> Bool {
        let end = s.open ? max(s.endDate, now) : s.endDate
        return end.timeIntervalSince(s.startDate) > systemLimit
    }

    public static func decide(run: Run?, wanted: WidgetFeed.Shoot?, reason: Reason, now: Date) -> Action {
        guard let wanted else { return run == nil ? .none : .end }
        guard let run else { return .start }
        if run.shootId != wanted.id { return .restart }
        // «Продлевать»: при каждом возврате в приложение, пока день длинный. Не открыл дольше срока — система сама уберёт плашку.
        if reason == .foreground, isLongDay(wanted, at: now), now.timeIntervalSince(run.startedAt) >= minRestartAge { return .restart }
        return .update
    }
}
