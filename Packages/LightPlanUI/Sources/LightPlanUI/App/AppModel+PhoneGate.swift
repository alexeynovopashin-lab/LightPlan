import Foundation
import LightPlanDomain

/// Номер телефона для планировщика (Алексей 05.11, шаг 30ж.1): «телефон не нужен пользователям экрана Свет…
/// Если пользователь хочет пользоваться планировщиком, то там телефон обязателен». Записи не трогаются: съёмки
/// человека без номера лежат на месте, но открыть их без номера нельзя. Правило стоит в самих дверях (`openForm`,
/// `openCard`, вкладка, ссылки), а не на кнопках: новая кнопка пройдёт через ту же дверь.
extension AppModel {

    /// Есть номер, с которым открывается планировщик. Что считается номером — `TelFormat.opensPlanner`.
    public var hasPlannerPhone: Bool { TelFormat.opensPlanner(myPhone, country: telCountry) }

    /// Дверь: `true` — проходи. `false` — открыт лист, `next` выполнится после «Готово».
    @discardableResult
    func passPhoneGate(then next: @escaping () -> Void) -> Bool {
        guard plannerNeedsPhone, !hasPlannerPhone else { return true }
        phoneAskNext = next
        if !phoneAskOpen {
            phoneAskWas = myPhone
            phoneAskConfirmed = false
            phoneAskOpen = true
        }
        return false
    }

    /// Нажатие на вкладку. «Свет», «Карта» и «Настройки» открываются всегда.
    public func openTab(_ target: AppTab) {
        if target == .planner, !passPhoneGate(then: { [weak self] in self?.openTab(target) }) { return }
        tab = target
    }

    /// «Готово»: работает только с номером.
    public func confirmPhoneAsk() {
        guard hasPlannerPhone else { return }
        commitMyPhone()
        phoneAskConfirmed = true
        phoneAskOpen = false
    }

    /// Крестик.
    public func cancelPhoneAsk() {
        phoneAskOpen = false
    }

    /// Лист ушёл с экрана. Всё, кроме «Готово» (крестик, смахивание), — отказ: поле как было, путь забыт.
    public func phoneSheetGone() {
        let next = phoneAskNext, confirmed = phoneAskConfirmed, was = phoneAskWas
        phoneAskNext = nil
        phoneAskWas = nil
        phoneAskConfirmed = false
        phoneAskOpen = false
        if confirmed {
            next?()
        } else if let was {
            restoreMyPhone(was)
        }
    }
}
