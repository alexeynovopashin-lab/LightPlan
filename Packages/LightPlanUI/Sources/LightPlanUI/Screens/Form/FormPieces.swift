import SwiftUI
import LightPlanCore
import LightPlanDomain

/// Кирпичи формы записи (`#formOverlay` веба, итерация 23): заголовок группы,
/// группа со щелями вместо линий, строка-поле, капсула значения, кнопки шапки.
/// Числа — справка `docs/native_23_form_web_spec.md` § 2.2.

/// `.g-label`: 10, прописные, разрядка 1,2, 600, `--ink-7`, отступы 30 / 4 / 9.
struct FormGroupLabel: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold)).tracking(1.2).textCase(.uppercase)
            .foregroundStyle(Palette(scheme).ink7)
            .padding(.top, 30).padding(.horizontal, 4).padding(.bottom, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `.group`: подложка `--sheet`, скругление 14, строки разделены **щелью** цвета
/// страницы в 1 pt — светлых линий в форме нет (правило «разделитель — щель»).
struct FormGroup<Content: View>: View {
    var node = ""
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette(scheme)
        VStack(spacing: 0) {
            Group(subviews: content) { subs in
                ForEach(subs.indices, id: \.self) { i in
                    // Щель — не строка высотой 1 pt, а 1 pt внутри строки (`inset 0 1px 0 var(--surface)`):
                    // высота группы от неё не растёт.
                    subs[i].overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(pal.surface).frame(height: 1) }
                    }
                }
            }
        }
        .background(pal.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shotNode(node)
    }
}

/// Строка-поле: 16, поля 15, минимум 52, без подложки; подсказка `--ink-8`.
struct FormTextField: View {
    enum Kind { case text, name, phone }
    let placeholder: String
    @Binding var text: String
    var kind: Kind = .text
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette(scheme)
        field(pal)
            .font(.system(size: 16)).foregroundStyle(pal.ink)
            .padding(15)
            .frame(height: 48, alignment: .leading)
    }

    @ViewBuilder
    private func field(_ pal: Palette) -> some View {
        let f = TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(pal.ink8))
        #if os(iOS)
        switch kind {
        case .text: f
        case .name: f.textContentType(.name)
        case .phone: f.keyboardType(.phonePad).textContentType(.telephoneNumber).autocorrectionDisabled()
        }
        #else
        f
        #endif
    }
}

/// Капсула значения `.rv-v`: таблетка (999), поля 5 / 12, `--field`, 16 цифрами
/// одной ширины; раскрытая — латунная (`rgba(226,164,76,.16)` и `--brass`).
struct FormCapsule: View {
    var node = ""
    let text: String
    let open: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette(scheme)
        Button(action: action) {
            Text(text)
                .font(.system(size: 16).monospacedDigit())
                .lineLimit(1)
                .foregroundStyle(open ? pal.brass : pal.ink)
                .padding(.horizontal, 12)
                .frame(minWidth: 72, minHeight: 28)
                .background(open ? Color(hex: 0xE2A44C, alpha: 0.16) : pal.field, in: Capsule())
                .fixedSize()
        }
        .shotNode(node, text: text)
        .buttonStyle(.plain)
    }
}

/// Кнопка шапки: круг 40, знак 18 линией 2,2. Крестик — стекло; галочка —
/// сплошная `--ink` со знаком цвета страницы.
struct FormBarButton: View {
    enum Kind { case close, save }
    var node = ""
    let kind: Kind
    let label: String
    /// `false` — «Сохранить» не нажимается (дата не названа, время занято); причина стоит на экране формы.
    var enabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette(scheme)
        let face = Icon(kind == .close ? "close" : "check", size: 18, line: 2.2)
            .foregroundStyle(kind == .close ? pal.ink3 : pal.surface)
            .frame(width: 40, height: 40)
        Button(action: action) {
            if kind == .close {
                face.glassEffect(.regular, in: Circle())
            } else {
                face.background(Circle().fill(pal.ink))
            }
        }
        // Нажатие ловит весь круг: стекло нажатий не ловит, и «✕» срабатывал,
        // только если палец попал в линию креста (телефон, 29.09 — «кнопка
        // глючит»; симулятор: внутри круга мимо линии — не закрывает).
        .contentShape(Circle())
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .shotNode(node)
        .accessibilityLabel(label)
    }
}

/// Плитка жанра `.tool`: знак 22 линией 1,5, подпись 10; выбранная — латунь на `--press-warm`.
/// Уточнение (`sub`) занимает плитку своим знаком; черта под подписью (`.hasub`,
/// 10 × 1,5 на 3 от низа, 0,3) — единственный намёк, что уточнения есть; у
/// раскрытой — 14 и 0,9.
struct GenreTile: View {
    enum Marker { case closed, open }
    let genre: Genre
    var sub: SubGenre? = nil
    let name: String
    let on: Bool
    var marker: Marker? = nil
    let action: () -> Void
    /// Удержание 0,42 с (веб `MB_HOLD`). Есть — плитка ловит тап и удержание сама:
    /// у `Button` отпущенный после удержания палец давал ещё и тап, и панель,
    /// раскрытая удержанием, тут же закрывалась (Алексей, телефон, 26.09).
    var hold: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette(scheme)
        if let hold {
            face(pal)
                .gesture(LongPressGesture(minimumDuration: 0.42, maximumDistance: 10).onEnded { _ in hold() }
                    .exclusively(before: TapGesture().onEnded { action() }))
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { action() }
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? .isSelected : [])
        } else {
            Button(action: action) { face(pal) }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? .isSelected : [])
        }
    }

    private func face(_ pal: Palette) -> some View {
        VStack(spacing: 6) {
            if let sub { Icon(sub.iconName, size: 22, line: 1.5) } else { Icon(genre: genre.rawValue, size: 22, line: 1.5) }
            Text(name).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(on ? pal.brass : pal.ink5)
        .frame(maxWidth: .infinity)
        .padding(.top, 11).padding(.horizontal, 2).padding(.bottom, 9)
        .overlay(alignment: .bottom) {
            if let marker {
                RoundedRectangle(cornerRadius: 1).fill(on ? pal.brass : pal.ink5)
                    .frame(width: marker == .open ? 14 : 10, height: 1.5)
                    .opacity(marker == .open ? 0.9 : 0.3)
                    .padding(.bottom, 3)
            }
        }
        .background(on ? pal.pressWarm : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Шаговый ввод `.stepper`: кнопки 38 × 34 радиус 10 `--press`, поле 58 радиус 9 `--field`.
struct FormStepper: View {
    let value: Int
    let step: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let pal = Palette(scheme)
        HStack(spacing: 6) {
            button("−", pal) { onChange(max(range.lowerBound, value - step)) }
            Text(value == 0 ? "—" : "\(value)")
                .font(.system(size: 16).monospacedDigit()).foregroundStyle(pal.ink)
                .frame(width: 58, height: 34)
                .background(pal.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            button("+", pal) { onChange(min(range.upperBound, value + step)) }
        }
    }
    private func button(_ s: String, _ pal: Palette, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(s).font(.system(size: 19)).foregroundStyle(pal.ink)
                .frame(width: 38, height: 34)
                .background(pal.press, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Шестерёнка `.gear` у «Жанра» и «Оплаты»: у веба она своя, встроенная в
/// разметку (`#fGear`, `#fPayGear`), а не знак библиотеки — `gear` в
/// `icons.js` это солнышко «настроек» (Алексей, телефон, 27.09). Путь — тот же
/// круг r 3,2 и зубцы веба, дуги переведены в кубики `Tools/icons2assets.js`.
struct FormGearIcon: View {
    static let path = IconArt.path(from: "M15.2 12C15.2 13.7673 13.7673 15.2 12 15.2C10.2327 15.2 8.8 13.7673 8.8 12C8.8 10.2327 10.2327 8.8 12 8.8C13.7673 8.8 15.2 10.2327 15.2 12ZM19.4 15C19.1277 15.6171 19.2583 16.3378 19.73 16.82L19.79 16.88C20.5715 17.6615 20.5715 18.9285 19.79 19.71C19.0085 20.4915 17.7415 20.4915 16.96 19.71L16.9 19.65C16.4178 19.1783 15.6971 19.0477 15.08 19.32C14.4755 19.5791 14.0826 20.1724 14.08 20.83L14.08 21C14.08 22.1046 13.1846 23 12.08 23C10.9754 23 10.08 22.1046 10.08 21L10.08 20.91C10.0642 20.2327 9.6359 19.6339 9 19.4C8.3829 19.1277 7.6622 19.2583 7.18 19.73L7.12 19.79C6.3385 20.5715 5.0715 20.5715 4.29 19.79C3.5085 19.0085 3.5085 17.7415 4.29 16.96L4.35 16.9C4.8217 16.4178 4.9523 15.6971 4.68 15.08C4.4209 14.4755 3.8276 14.0826 3.17 14.08L3 14.08C1.8954 14.08 1 13.1846 1 12.08C1 10.9754 1.8954 10.08 3 10.08L3.09 10.08C3.7673 10.0642 4.3661 9.6359 4.6 9C4.8723 8.3829 4.7417 7.6622 4.27 7.18L4.21 7.12C3.4285 6.3385 3.4285 5.0715 4.21 4.29C4.9915 3.5085 6.2585 3.5085 7.04 4.29L7.1 4.35C7.5822 4.8217 8.3029 4.9523 8.92 4.68L9 4.68C9.6045 4.4209 9.9974 3.8276 10 3.17L10 3C10 1.8954 10.8954 1 12 1C13.1046 1 14 1.8954 14 3L14 3.09C14.0026 3.7476 14.3955 4.3409 15 4.6C15.6171 4.8723 16.3378 4.7417 16.82 4.27L16.88 4.21C17.6615 3.4285 18.9285 3.4285 19.71 4.21C20.4915 4.9915 20.4915 6.2585 19.71 7.04L19.65 7.1C19.1783 7.5822 19.0477 8.3029 19.32 8.92L19.32 9C19.5791 9.6045 20.1724 9.9974 20.83 10L21 10C22.1046 10 23 10.8954 23 12C23 13.1046 22.1046 14 21 14L20.91 14C20.2524 14.0026 19.6591 14.3955 19.4 15Z"[...])
    var size: CGFloat = 21
    var body: some View {
        IconOutline(path: Self.path)
            .stroke(style: StrokeStyle(lineWidth: 1.6 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#if os(iOS)
import UIKit

/// Тап мимо поля убирает клавиатуру. У цифровой клавиатуры нет «Готово», а
/// `scrollDismissesKeyboard` ловит только протяжку: выйти из поля суммы можно
/// было, лишь свернув блок (Алексей, телефон, 27.09). Распознаватель стоит на
/// окне и касаний не отнимает (`cancelsTouchesInView = false`): кнопки и
/// чипсы работают как прежде, тап по другому полю переводит ввод туда.
struct KeyboardDismissOnTap: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Probe {
        let v = Probe()
        v.coordinator = context.coordinator
        v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ uiView: Probe, context: Context) {}
    static func dismantleUIView(_ uiView: Probe, coordinator: Coordinator) { coordinator.detach() }

    final class Probe: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let w = window { coordinator?.attach(to: w) } else { coordinator?.detach() }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var tap: UITapGestureRecognizer?
        func attach(to w: UIWindow) {
            guard tap == nil else { return }
            let t = UITapGestureRecognizer(target: self, action: #selector(hit))
            t.cancelsTouchesInView = false
            t.delegate = self
            w.addGestureRecognizer(t)
            tap = t
        }
        func detach() {
            if let t = tap { t.view?.removeGestureRecognizer(t) }
            tap = nil
        }
        @objc private func hit(_ g: UITapGestureRecognizer) { g.view?.endEditing(true) }
        /// Тап по самому полю ввода — не мимо.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var v = touch.view
            while let x = v { if x is UITextField || x is UITextView { return false }; v = x.superview }
            return true
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
    }
}
#endif
