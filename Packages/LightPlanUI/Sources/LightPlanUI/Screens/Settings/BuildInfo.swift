import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Какая сборка стоит на телефоне: ветка, коммит, день сборки (шаг 28в).
///
/// Три ключа в Info.plist пишет фаза сборки `Tools/stamp_build.sh` — из git той
/// папки, откуда собирали. Сборка без git (архив) или без ключей — «неизвестна»,
/// падать нечему. Тот же формат печатает `make phone ARGS="list"`
/// (`Tools/build_stamp.sh line`).
struct BuildInfo: Equatable {
    let branch: String
    let sha: String
    /// День сборки, `ГГГГ-ММ-ДД` — на экране `ДД.ММ`.
    let day: String

    static let keyBranch = "LPBuildBranch", keySha = "LPBuildSha", keyDay = "LPBuildDate"

    /// Все три ключа на месте и непусты, иначе `nil` — «неизвестна».
    init?(info: [String: Any]?) {
        func value(_ key: String) -> String? {
            let s = (info?[key] as? String)?.trimmingCharacters(in: .whitespaces)
            return s?.isEmpty == false ? s : nil
        }
        guard let branch = value(Self.keyBranch), let sha = value(Self.keySha), let day = value(Self.keyDay)
        else { return nil }
        self.branch = branch; self.sha = sha; self.day = day
    }

    static func current(_ bundle: Bundle = .main) -> BuildInfo? {
        BuildInfo(info: bundle.infoDictionary)
    }

    /// `ГГГГ-ММ-ДД` → `ДД.ММ`; иной вид даты остаётся как есть.
    var shortDay: String {
        let p = day.split(separator: "-")
        return p.count == 3 ? "\(p[2]).\(p[1])" : day
    }

    /// Шаблон и «неизвестна» приходят готовыми, чтобы формат проверялся и без каталога слов.
    static func line(_ info: BuildInfo?, template: String, unknown: String) -> String {
        guard let info else { return unknown }
        return Lexicon.substitute(template, ["branch": info.branch, "sha": info.sha, "date": info.shortDay])
    }

    static func line(_ info: BuildInfo?, _ t: Lexicon) -> String {
        line(info, template: t.t("set.buildLine"), unknown: t.t("set.buildUnknown"))
    }

    /// Тап: в приёмник уходит ровно та строка, что на экране. Алексей присылает её в чат.
    static func copyLine(_ info: BuildInfo?, _ t: Lexicon, to sink: (String) -> Void) {
        sink(line(info, t))
    }

    @MainActor static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// Строка внизу «Настроек»: приглушённая, не крупнее подписей (12 pt, `ink6`);
/// тап кладёт её в буфер.
struct BuildLine: View {
    let info: BuildInfo?
    let lexicon: Lexicon
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button { BuildInfo.copyLine(info, lexicon, to: BuildInfo.copy) } label: {
            Text(BuildInfo.line(info, lexicon))
                .font(.system(size: 12))
                .foregroundStyle(Palette(colorScheme).ink6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
