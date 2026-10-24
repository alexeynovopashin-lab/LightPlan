import SwiftUI
import LightPlanData
import LightPlanDomain
#if os(iOS)
import Contacts
import ContactsUI
import UIKit

/// «Из Контактов» (шаг К7, справка § 5): системный выбор контакта. Работает **без разрешения** — книгу показывает
/// система, приложению достаётся только выбранный контакт. У контакта с одним номером выбор — сам контакт; с
/// несколькими — нажатый номер.
///
/// Лист `CNContactPickerViewController` нельзя вложить в `.sheet`: он показывается сам, поверх невидимого
/// контроллера-подставки.
struct ContactPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (FoundContact) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.isUserInteractionEnabled = false
        return vc
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        // Один номер (или ни одного) — выбирается контакт целиком; несколько — человек нажимает нужный.
        picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count <= 1")
        DispatchQueue.main.async { host.present(picker, animated: true) }
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPickerPresenter
        init(_ parent: ContactPickerPresenter) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.isPresented = false
            parent.onPick(CNContactsStore.found(contact))
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
            parent.isPresented = false
            var f = CNContactsStore.found(property.contact)
            if let n = property.value as? CNPhoneNumber { f.phones = [n.stringValue] }
            parent.onPick(f)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { parent.isPresented = false }
    }
}

extension View {
    /// Системный выбор контакта поверх экрана, пока `isPresented`.
    func contactPicker(isPresented: Binding<Bool>, onPick: @escaping (FoundContact) -> Void) -> some View {
        background(ContactPickerPresenter(isPresented: isPresented, onPick: onPick).frame(width: 0, height: 0))
    }
}
#else
extension View {
    func contactPicker(isPresented: Binding<Bool>, onPick: @escaping (FoundContact) -> Void) -> some View { self }
}
#endif
