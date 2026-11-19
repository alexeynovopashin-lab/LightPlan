import Foundation
import LightPlanData
import LightPlanDomain

/// 31.11 «Копия перед перезаписью данных». Файл данных не прочитался — человек узнаёт об этом системным окном на
/// старте, а не видит молча пустое приложение; копия исходника уже лежит рядом с файлом (`Store.load`).
extension AppModel {
    /// Записи старта (клиенты из съёмок, годовщины, пустые жанровые папки мудборда) — раньше жили в `live()`.
    /// Файл не разобрался совсем или не прочитался — старт его не пишет: до 31.11 именно запись пустых жанровых
    /// папок клала пустой снимок поверх повреждённого файла сразу при запуске. Первая запись — от правки человека,
    /// и к ней копия уже лежит. Разобралась часть — прочитанное пишется сразу: следующий запуск откроет файл без
    /// окна, а исходник целиком остался копией.
    static func settleStart(_ snapshot: inout Snapshot, store: Store?, damage: StoreDamage?, now: Date = Date()) async {
        let writes: Bool
        switch damage?.kind {
        case nil: writes = true
        case .salvaged?: writes = damage?.writesHeld == false
        case .damaged?, .unreadable?: writes = false
        }
        // Клиенты из уже записанных съёмок — один раз на файл данных (шаг К1, справка `clients_reference.md` § 3.8).
        let assembled = assembleClients(into: &snapshot, language: AppLanguage.current, now: now)
        // Годовщина пары из свадьбы — в снимок (К6, § 2.4): экраны считают её сами, запись — для облака.
        let settled = settleAnniversaries(in: &snapshot, now: now)
        // Пустая жанровая папка на каждый включённый жанр — один раз, пишется сразу (веб `mbSeeded`).
        let seeded = RefLibrary.seedGenreFolders(in: &snapshot.extra,
                                                 genres: Moodboard.enabledGenres(snapshot.genres).map(\.rawValue),
                                                 newId: { UUID().uuidString.lowercased() },
                                                 now: now.timeIntervalSince1970 * 1000)
        let salvaged: Bool = if case .salvaged? = damage?.kind { true } else { false }
        guard writes, assembled || settled || seeded || salvaged else { return }
        try? await store?.saveNow(snapshot)
    }

    /// Заголовок и текст окна о файле данных; `nil` — с файлом всё хорошо (или окно уже закрыли).
    /// Облако подключено и его глава видна (не «Просто») — текст подсказывает «Восстановить из облака» (31.1);
    /// при нечитаемом файле — нет: сначала перезапуск, иначе копия с Диска легла бы на неперечитанный файл.
    var dataDamageWords: (title: String, message: String)? {
        guard let damage = dataDamage else { return nil }
        let t = lexicon
        let cloudHint = cloud.connected && settings.mode != .simple ? " " + t.t("data.brokenCloud") : ""
        if damage.writesHeld { return (t.t("data.unreadT"), t.t("data.unreadM")) }
        switch damage.kind {
        case .salvaged(let n): return (t.t("data.partT"), t.t("data.partM", ["n": String(n)]) + cloudHint)
        case .damaged, .unreadable: return (t.t("data.brokenT"), t.t("data.brokenM") + cloudHint)
        }
    }

    /// «Понятно»: окно больше не показывается в этом запуске. Файл всё ещё повреждён — при следующем запуске окно
    /// придёт снова (копия та же, новой не будет): пустое приложение без объяснения хуже лишнего окна.
    func dismissDataDamage() { dataDamage = nil }
}
