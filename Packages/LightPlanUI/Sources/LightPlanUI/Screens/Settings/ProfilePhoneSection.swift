import SwiftUI
import LightPlanDomain
#if os(iOS)
import UIKit
#endif

/// «Мой телефон», «ID приложения» и «Прежние ID» в главе «Профиль» (веб `#setOvProfile`,
/// итерация 23). Номер хранится целиком, международной записью; в поле стоит
/// только национальная часть, код страны — блоком слева. ID — от мобильного номера.
struct ProfilePhoneSection: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase
    @FocusState private var focused: Bool
    @State private var countrySheet = false
    @State private var copied = false

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let country = app.telCountry
        SecLabel(text: t.t("set.myPhone"))
        HStack(spacing: 10) {
            Button { countrySheet = true } label: {
                HStack(spacing: 4) {
                    Text("+" + country.cc).font(.system(size: 16).monospacedDigit())
                    Icon("chevron", size: 14, line: 2.2).rotationEffect(.degrees(90))
                }
                .foregroundStyle(pal.ink)
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(pal.field, in: Capsule())
            }
            .buttonStyle(.plain)
            TextField("", text: national, prompt: Text(TelFormat.nationalFormatted(country.example, country: country)).foregroundStyle(pal.ink8))
                .font(.system(size: 16).monospacedDigit()).foregroundStyle(pal.ink)
                .focused($focused)
                .phoneKeyboard()
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
        .onChange(of: focused) { _, on in if !on { app.commitMyPhone() } }
        .onChange(of: phase) { _, _ in app.commitMyPhone() }
        .onDisappear { app.commitMyPhone() }
        .sheet(isPresented: $countrySheet) { CountrySheet(app: app) }

        // Страна по номеру: где кодов несколько, молчать нельзя — спрашиваем.
        let fit = TelFormat.countriesFitting(app.myPhone).filter { $0 != country }
        if !app.myPhone.isEmpty, app.myAppId.isEmpty, !fit.isEmpty {
            Text(t.t("tel.ccAsk")).font(.system(size: 13)).foregroundStyle(pal.ink4).padding(.horizontal, 24).padding(.top, 4)
            HStack(spacing: 8) {
                ForEach(fit, id: \.iso) { c in
                    Button(regionName(c.iso) + " +" + c.cc) { pick(c) }
                        .font(.system(size: 13)).foregroundStyle(pal.ink3)
                        .padding(.vertical, 10).padding(.horizontal, 15)
                        .background(pal.press, in: Capsule())
                }
            }
            .padding(.horizontal, 24).padding(.top, 8)
        }

        SecLabel(text: t.t("set.appId"))
        Button(action: copy) {
            SetItemRow(icon: nil, title: copied ? t.t("set.appIdCopied") : idTitle(t), value: "", chevron: false)
        }
        .buttonStyle(.plain)
        SetNote(text: t.t("set.appIdNote"))

        let was = app.myPreviousIds
        if !was.isEmpty {
            SecLabel(text: t.t("set.appIdWas"))
            ForEach(was, id: \.self) { e in
                SetItemRow(icon: nil, title: e.was, value: date(e.at), chevron: false)
            }
            SetNote(text: t.t("set.appIdWasNote"))
        }
    }

    private func idTitle(_ t: Lexicon) -> String {
        if !app.myAppId.isEmpty { return app.myAppId }
        return app.myPhone.isEmpty ? t.t("set.appIdNone") : t.t("set.appIdNotMobile")
    }

    private func copy() {
        guard !app.myAppId.isEmpty else { focused = true; return }
        #if os(iOS)
        UIPasteboard.general.string = app.myAppId
        #endif
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
    }

    private func date(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return "" }
        return DateText(language: app.language).dMonShortYear(d)
    }

    /// Поле: национальная часть; вставка с кодом другой страны переставляет и блок кода.
    private var national: Binding<String> {
        Binding(get: { TelFormat.national(of: app.myPhone, country: app.telCountry) }, set: { v in
            let r = TelFormat.natIn(v, country: app.telCountry)
            if let c = r.country { app.setTelCountry(c) }
            app.setMyPhone(TelFormat.join(national: r.national, country: r.country ?? app.telCountry))
            app.followCountryOfPhone()
        })
    }

    private func pick(_ c: TelCountry) {
        app.setTelCountry(c)
        let d = TelFormat.digits(app.myPhone)
        app.setMyPhone(TelFormat.format("+" + d, country: c))
        app.commitMyPhone()
    }

    private func regionName(_ iso: String) -> String {
        Locale(identifier: app.language).localizedString(forRegionCode: iso) ?? iso
    }
}

/// «Код страны»: поиск по названию, +коду и ISO; выбор оставляет набранные цифры и переразбивает их.
struct CountrySheet: View {
    @Bindable var app: AppModel
    @State private var query = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let pal = Palette(scheme)
        let t = app.lexicon
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = TelCountry.all
            .map { ($0, Locale(identifier: app.language).localizedString(forRegionCode: $0.iso) ?? $0.iso) }
            .filter { q.isEmpty || $0.1.lowercased().contains(q) || $0.0.cc.contains(q.replacingOccurrences(of: "+", with: "")) || $0.0.iso.lowercased() == q }
            .sorted { $0.1 < $1.1 }
        ScrollView {
            VStack(spacing: 0) {
                Text(t.t("tel.ccT")).font(webFont(19, 650)).foregroundStyle(pal.ink).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                TextField("", text: $query, prompt: Text(t.t("tel.ccFind")).foregroundStyle(pal.ink8))
                    .font(.system(size: 16)).foregroundStyle(pal.ink)
                    .padding(12).background(pal.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                ForEach(rows, id: \.0.iso) { c, name in
                    Button { choose(c) } label: {
                        HStack {
                            Text(name).font(.system(size: 16)).foregroundStyle(pal.ink)
                            Spacer()
                            Text("+" + c.cc).font(.system(size: 15).monospacedDigit()).foregroundStyle(pal.ink4)
                            if c == app.telCountry { Icon("check", size: 18, line: 2).foregroundStyle(pal.brass) }
                        }
                        .padding(.vertical, 12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .presentationDetents([.large])
    }

    private func choose(_ c: TelCountry) {
        let digits = TelFormat.digits(app.myPhone)
        app.setTelCountry(c)
        if !digits.isEmpty { app.setMyPhone(TelFormat.join(national: TelFormat.natIn("+" + digits, country: c).national, country: c)) }
        dismiss()
    }
}

private extension View {
    @ViewBuilder func phoneKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.phonePad).textContentType(.telephoneNumber)
        #else
        self
        #endif
    }
}
