import Foundation
import LightPlanCore
import LightPlanData

/// Слой AR (шаги 29.8в, 29.8в.3): вход и выход. Экран получает место и момент.
extension AppModel {
    /// Открыть AR в этот момент. Момент по умолчанию — «сейчас».
    ///
    /// Место — то, где стоит телефон (последняя точка, которую приложение уже держит; если доступ к геопозиции
    /// уже дан — свежая, без нового системного окна). Телефон положения не дал — берётся `chosen`, место,
    /// выбранное в приложении, и плашка на экране говорит об этом.
    func openSunAR(chosen: Place, moment: Moment = Moment(Date())) {
        sunARSession += 1
        sunAR = SunARTarget(choice: .resolve(phone: phoneSpot(), chosen: chosen), moment: moment)
        let session = sunARSession
        Task { await refreshSunARPhone(chosen: chosen, session: session) }
    }

    /// Прямо заданное место (тесты, отладка): без обращения к телефону.
    func openSunAR(place: Place, moment: Moment = Moment(Date())) {
        sunARSession += 1
        sunAR = SunARTarget(place: place, moment: moment)
    }

    func closeSunAR() {
        sunARSession += 1
        sunAR = nil
    }

    /// Место телефона по последнему ответу «где я». Пояс — кэш зон приложения (настоящий, если геокодер уже
    /// отвечал для этих полградуса, иначе оценка по долготе). `nil` — телефон положения не давал.
    func phoneSpot() -> Place? {
        #if DEBUG
        if let c = Self.debugPhoneSpot { return c }
        #endif
        guard case .fix(let c)? = place.lastDeviceResult else { return nil }
        return Place(latitude: c.latitude, longitude: c.longitude, zone: place.zones.zoneOrEstimate(at: c))
    }

    /// Свежая точка телефона, пока экран открыт: только если доступ уже дан (AR сам разрешения не просит),
    /// и без сдвига места приложения. Настоящий пояс — от геокодера, если он ещё не известен.
    private func refreshSunARPhone(chosen: Place, session: Int) async {
        #if DEBUG
        if Self.debugPhoneSpot != nil { return }
        #endif
        guard locator.isAlreadyAuthorized else { return }
        guard case .fix(let c) = await locator.currentFix(), session == sunARSession, sunAR != nil else { return }
        _ = await place.learnZone(at: c)
        guard session == sunARSession, sunAR != nil else { return }
        let phone = Place(latitude: c.latitude, longitude: c.longitude, zone: place.zones.zoneOrEstimate(at: c))
        sunAR?.choice = .resolve(phone: phone, chosen: chosen)
    }

    #if DEBUG
    /// `-LPSunARPhone lat,lon,Zone/Id` — подставное место телефона (в симуляторе его нет).
    static var debugPhoneSpot: Place? {
        guard let s = UserDefaults.standard.string(forKey: "LPSunARPhone") else { return nil }
        let p = s.split(separator: ",").map(String.init)
        guard p.count == 3, let la = Double(p[0]), let lo = Double(p[1]), let z = ZoneID(p[2]) else { return nil }
        return Place(latitude: la, longitude: lo, zone: z)
    }

    /// Снимок и проверка в симуляторе: `-LPSunAR 1` открывает экран сразу на месте приложения; момент —
    /// `-LPSunARMoment 2026-06-21T15:30:00Z`, по умолчанию «сейчас».
    func debugOpenSunAR() {
        let d = UserDefaults.standard
        guard d.string(forKey: "LPSunAR") != nil else { return }
        var moment = Moment(Date())
        if let s = d.string(forKey: "LPSunARMoment"), let date = ISO8601DateFormatter().date(from: s) {
            moment = Moment(date)
        }
        openSunAR(chosen: light.timebar.place, moment: moment)
    }
    #endif
}
