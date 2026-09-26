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
        .buttonStyle(.plain)
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
