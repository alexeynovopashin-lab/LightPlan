import Foundation
import LightPlanCore
import LightPlanData

/// Что показывает плашка перед входом в AR и почему она появилась (шаг 29.8в.4).
struct SunAREntry: Equatable {
    enum Reason: Equatable {
        /// Доступ к геопозиции ещё не спрашивали / служба выключена.
        case off
        /// Отказано или ограничено системой.
        case denied
        /// Доступ есть, точку получить не удалось.
        case noFix
        /// Доступ есть, ищем точку.
        case locating
        /// Выбранное в приложении место дальше порога (50 км) от телефона.
        case far(km: Double)
    }

    var chosen: Place
    /// Название выбранного места — как в шапке приложения.
    var name: String
    var moment: Moment
    var reason: Reason
}

/// Слой AR (шаги 29.8в, 29.8в.3, 29.8в.4): вход и выход. Экран получает место и момент.
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

    /// Кнопка «AR» карты: место приложения, момент — «сейчас» по часам приложения (29.8в.12). Раньше вход нёс
    /// время, выбранное на таймбаре карты, и AR открывался не на «сейчас».
    func enterSunAR() {
        beginSunAR(chosen: light.timebar.place, name: light.locationName, moment: Moment(now()))
    }

    /// Вход в AR с кнопки карты (шаг 29.8в.4). Слово Алексея 14.10: «режим AR всегда включается там, где находится
    /// пользователь»; если геопозиции нет или выбранное в приложении место дальше 50 км от телефона — плашка с
    /// двумя действиями перед переходом. Выбор живёт только на этот вход и место приложения не меняет.
    func beginSunAR(chosen: Place, name: String, moment: Moment = Moment(Date())) {
        sunAREntryBusy = false
        var authorized = locator.isAlreadyAuthorized
        #if DEBUG
        if Self.debugPhoneSpot != nil { authorized = true }
        #endif
        guard authorized else {
            // Ещё не спрашивали — «выключена»; отказали или ограничено — «нет доступа».
            sunAREntry = SunAREntry(chosen: chosen, name: name, moment: moment,
                                    reason: locator.needsPermission ? .off : .denied)
            return
        }
        // Доступ есть: решение — по свежей точке, а не по старой (ревью GPT к 4f8cb91: со старой точкой экран молча
        // переключался на новую уже после входа). Ответ быстрый — плашки нет; медленный — через 0,4 с «Определяю место…».
        sunAREntry = nil
        sunARSession += 1
        let session = sunARSession
        Task { await decideSunAREntry(chosen: chosen, name: name, moment: moment, session: session) }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard session == sunARSession, sunAR == nil, sunAREntry == nil else { return }
            sunAREntry = SunAREntry(chosen: chosen, name: name, moment: moment, reason: .locating)
        }
    }

    /// Свежая точка телефона и решение: рядом — AR сразу; далеко — плашка с расстоянием; нет точки — плашка с
    /// причиной. Точки не пришло (нет сигнала) — старая точка лучше, чем ничего. Каждый шаг после ожидания
    /// проверяет номер захода: ответ от отменённого входа ничего не меняет.
    private func decideSunAREntry(chosen: Place, name: String, moment: Moment, session: Int) async {
        let fix = await deviceFixForAR()
        guard session == sunARSession, sunAR == nil else { return }
        var phone: Place?
        switch fix {
        case .fix(let c): phone = await phonePlace(at: c)
        case .unavailable: phone = phoneSpot()
        case .denied, .restricted: break
        }
        guard session == sunARSession, sunAR == nil else { return }
        guard let phone else {
            let reason: SunAREntry.Reason = fix == .unavailable ? .noFix : .denied
            sunAREntry = SunAREntry(chosen: chosen, name: name, moment: moment, reason: reason)
            return
        }
        if case .phone(_, let far?) = SunARPlaceChoice.resolve(phone: phone, chosen: chosen) {
            sunAREntry = SunAREntry(chosen: chosen, name: name, moment: moment, reason: .far(km: far))
        } else {
            sunAREntry = nil
            openSunAR(phone: phone, chosen: chosen, moment: moment)
        }
    }

    /// «Использовать моё местоположение»: системное окно, если ещё не спрашивали; отказ — плашка снова, с
    /// пояснением и вторым вариантом.
    func sunARUseMyLocation() {
        guard let entry = sunAREntry, !sunAREntryBusy else { return }
        sunAREntryBusy = true
        sunARSession += 1
        let session = sunARSession
        Task {
            let fix = await deviceFixForAR()
            // Номер входа — первым: ответ отменённого входа не трогает ничего, в том числе занятость нового
            // (закрыли плашку, открыли снова и нажали — старый ответ не должен снять замок с нового нажатия).
            // Закрытие и «Оставить» сами снимают занятость.
            guard session == sunARSession else { return }
            sunAREntryBusy = false
            guard sunAREntry != nil else { return }
            switch fix {
            case .fix(let c):
                let phone = await phonePlace(at: c)
                guard sunAREntry != nil, session == sunARSession else { return }
                sunAREntry = nil
                openSunAR(phone: phone, chosen: entry.chosen, moment: entry.moment)
            case .denied, .restricted: sunAREntry?.reason = .denied
            case .unavailable: sunAREntry?.reason = .noFix
            }
        }
    }

    /// «Оставить «<место>»»: экран считает для выбранного в приложении места, только на этот вход.
    func sunARKeepChosen() {
        guard let entry = sunAREntry else { return }
        sunAREntry = nil
        sunAREntryBusy = false
        sunARSession += 1
        sunAR = SunARTarget(choice: .chosen(entry.chosen), moment: entry.moment)
    }

    func dismissSunAREntry() {
        sunAREntry = nil
        sunAREntryBusy = false
        sunARSession += 1
    }

    /// Точка телефона. В отладочной сборке `-LPSunARPhone` подставляет её (в симуляторе датчика места нет).
    private func deviceFixForAR() async -> DeviceFix {
        #if DEBUG
        if let p = Self.debugPhoneSpot { return .fix(GeoCoordinate(latitude: p.latitude, longitude: p.longitude)) }
        #endif
        return await locator.currentFix()
    }

    private func phonePlace(at c: GeoCoordinate) async -> Place {
        #if DEBUG
        if let p = Self.debugPhoneSpot { return p }
        #endif
        _ = await place.learnZone(at: c)
        return Place(latitude: c.latitude, longitude: c.longitude, zone: place.zones.zoneOrEstimate(at: c))
    }

    /// AR по месту телефона, найденному на входе: экран считает для него, плашки «выбранное далеко» не будет —
    /// человек выбрал своё место сам.
    func openSunAR(phone: Place, chosen: Place, moment: Moment) {
        sunARSession += 1
        sunAR = SunARTarget(choice: .phone(phone, chosenFarKm: nil), moment: moment)
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
        if d.bool(forKey: "LPSunAREntry") {
            beginSunAR(chosen: light.timebar.place, name: light.locationName, moment: moment)
        } else {
            openSunAR(chosen: light.timebar.place, moment: moment)
        }
    }
    #endif
}
