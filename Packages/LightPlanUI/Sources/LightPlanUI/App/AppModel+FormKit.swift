import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

/// Оборудование и документы заказа в форме (итерация 24, шаг 4а). Правила —
/// в `EventForm` (`FormKit.swift`); здесь — общий список техники из настроек.
extension AppModel {

    /// Общий список оборудования (веб `equipment`).
    public var equipment: [String] { snapshot.equipment }

    public func toggleFormGear(_ name: String) {
        guard var f = form else { return }
        f.toggleGear(name)
        form = f
        formChanged()
    }

    /// Новая позиция в общий список — и сразу на эту съёмку (веб `#kitAdd`).
    public func addEquipment(_ name: String) {
        guard var f = form else { return }
        var list = snapshot.equipment
        Kit.add(name, to: &list, form: &f)
        snapshot.equipment = list
        form = f
        persist()
        formChanged()
    }

    /// Позиция убрана из общего списка (веб `[data-kit-x]`): список пишется сразу.
    public func removeEquipment(at i: Int) {
        guard var f = form else { return }
        var list = snapshot.equipment
        Kit.remove(at: i, from: &list, form: &f)
        snapshot.equipment = list
        form = f
        persist()
        formChanged()
    }

    /// Виды документов по практике (веб `practiceSpec().docs`).
    public var docKinds: [DocKind] { (LightPlanDomain.Practice(rawValue: settings.practice.rawValue) ?? .ru).docKinds }

    public func addFormDocLink(_ url: String, kind: DocKind?, title: String? = nil) {
        guard var f = form else { return }
        f.addDocLink(url, kind: kind, title: title)
        form = f
        formChanged()
    }

    public func removeFormDoc(at i: Int) {
        guard var f = form else { return }
        f.removeDoc(at: i)
        form = f
        formChanged()
    }
}
