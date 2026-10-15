import SwiftUI
import LightPlanCore
import LightPlanData

/// Плашка перед входом в AR (шаг 29.8в.4). Слово Алексея 14.10: «если гео не вкл или приложение понимает, что стоит
/// другой город, оно сообщает ему, перед переходом в AR режим. Простая полупрозрачная плашка на матовом стекле.
/// Использовать моё местоположение / оставить "Барнаул" (пишем то место которое выбрано)».
///
/// Два действия. «Использовать моё местоположение»: если разрешения нет — системный запрос; отказ возвращает плашку
/// с пояснением и вторым вариантом. «Оставить «…»»: AR считает для выбранного в приложении места, только на этот
/// вход. Матовое стекло — системное `.glassEffect` (размывает фон), своей подделки нет (`Tools/check_glass.sh`).
struct SunAREntryPlate: View {
    @Bindable var app: AppModel
    let entry: SunAREntry
    @Environment(\.colorScheme) private var scheme

    private var t: Lexicon { app.lexicon }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { app.dismissSunAREntry() }
            VStack(spacing: 16) {
                Text(whyText)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .shotNode("ar.entry.why", text: whyText)
                VStack(spacing: 10) {
                    if entry.reason != .locating { useMine }
                    keep
                }
            }
            .foregroundStyle(.primary)
            .padding(20)
            .frame(maxWidth: 360)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 24)
            .shotNode("ar.entry", text: String(describing: entry.reason))
        }
        .transition(.opacity)
    }

    private var useMine: some View {
        let busy = app.sunAREntryBusy
        let label = busy ? t.t("ar.entry.busy") : t.t("ar.entry.useMine")
        return Button { app.sunARUseMyLocation() } label: {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: SunARInk.touch)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .glassEffect(.regular.tint(SunARInk.sunTint.opacity(0.35)).interactive(), in: Capsule())
        .shotNode("ar.entry.useMine", text: label)
    }

    private var keep: some View {
        let label = t.t("ar.entry.keep", ["name": entry.name])
        return Button { app.sunARKeepChosen() } label: {
            Text(label)
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: SunARInk.touch)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Capsule())
        .shotNode("ar.entry.keep", text: label)
    }

    private var whyText: String {
        switch entry.reason {
        case .off: return t.t("ar.entry.whyOff")
        case .denied: return t.t("ar.entry.whyDenied")
        case .noFix: return t.t("ar.entry.whyNoFix")
        case .locating: return t.t("ar.entry.busy")
        case .far(let km):
            let n = NumberText(language: app.language)
            let d = km < 10 ? n.num(km, digits: 1) : n.num(km.rounded(), digits: 0)
            return t.t("ar.entry.whyFar", ["d": t.t("pro.distKm", ["n": d])])
        }
    }
}
