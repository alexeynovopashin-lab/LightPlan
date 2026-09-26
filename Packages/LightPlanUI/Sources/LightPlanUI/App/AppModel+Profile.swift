import Foundation
import LightPlanCore
import LightPlanDomain

/// Профиль владельца (итерация 23): «Мой телефон», «ID приложения», «Прежние ID».
/// Лежат в `me` снимка: `phone`, `ids` (старые первыми), `telAt`, и `telCountry` рядом.
extension AppModel {

    private var meObject: [String: JSONValue] {
        if case .object(let o)? = snapshot.extra["me"] { return o }
        return [:]
    }

    private func setMe(_ key: String, _ value: JSONValue?) {
        var me = meObject
        me[key] = value
        snapshot.extra["me"] = .object(me)
    }

    /// Номер владельца как хранится: строка, как её показали.
    public var myPhone: String {
        if case .string(let p)? = meObject["phone"] { return p }
        return ""
    }

    /// ID приложения: «id» и международные цифры мобильного; пусто — номера нет или он не мобильный.
    public var myAppId: String { TelFormat.appId(myPhone, country: telCountry) }

    /// Прежние ID, новые первыми — так их читает человек (в снимке они старые первыми).
    public var myPreviousIds: [MyIdEntry] { storedIds.reversed() }

    private var storedIds: [MyIdEntry] {
        guard case .array(let a)? = meObject["ids"] else { return [] }
        return a.compactMap { v in
            guard case .object(let o) = v, case .string(let was)? = o["was"] else { return nil }
            if case .string(let at)? = o["at"] { return MyIdEntry(was: was, at: at) }
            return MyIdEntry(was: was, at: "")
        }
    }

    public func setTelCountry(_ c: TelCountry) {
        snapshot.extra["telCountry"] = .string(c.iso)
        persist()
    }

    /// Поле номера правят: хранится сразу, цепочка ID сдвигается на фиксации.
    public func setMyPhone(_ stored: String) {
        if telSnap == nil { telSnap = myPhone }
        setMe("phone", stored.isEmpty ? nil : .string(stored))
        persist()
    }

    /// Фиксация номера: уход из поля, с экрана или в фон (веб `myTelCommit`). Настоящая
    /// смена сдвигает цепочку прежних ID и ставит отметку времени.
    /// Вопрос «сначала копия» перед сменой — итерация 31 (копия) и 12 (файл).
    public func commitMyPhone() {
        let before = telSnap ?? myPhone, after = myPhone
        telSnap = after
        let iso = ISO8601DateFormatter().string(from: now())
        let r = MyIdChain.retire(storedIds, from: before, to: after, country: telCountry, at: iso)
        guard r.real else { return }
        setMe("ids", .array(r.list.map { .object(["was": .string($0.was), "at": .string($0.at)]) }))
        setMe("telAt", .string(iso))
        persist()
    }

    /// Страна идёт за номером молча, когда ответ один по коду (веб `telCcFollow`).
    public func followCountryOfPhone() {
        let fit = TelFormat.countriesFitting(myPhone)
        guard !fit.isEmpty, !fit.contains(telCountry), Set(fit.map(\.cc)).count == 1 else { return }
        setTelCountry(fit[0])
    }
}
