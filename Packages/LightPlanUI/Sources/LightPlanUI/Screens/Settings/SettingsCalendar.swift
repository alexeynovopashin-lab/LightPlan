import SwiftUI
import LightPlanData
#if os(iOS)
import UIKit
#endif

/// «Календарь» в главе «Съёмки» (шаг 30.1): тумблер «Съёмки в Календаре iPhone» и «Куда класть».
///
/// Тумблер — единственный момент, когда у системы просят доступ к календарю. Отказ ничего не ломает: тумблер
/// остаётся выключенным, строка под ним говорит, где доступ выдаётся. «Куда класть» стоит под включённым
/// тумблером — выбрать учётную запись, где календарь «Light Plan» заведётся (iCloud, Google, Exchange, сам
/// телефон); календарь переезжает, события ложатся в него заново. Высоты не заданы: строки растут вместе с
/// текстом, на узком экране пояснение просто переносится.
///
/// Там, где зеркала нет (Mac, снимки), остаётся прежняя приглушённая строка.
struct CalendarMirrorSection: View {
    @Bindable var app: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        let t = app.lexicon, pal = Palette(colorScheme)
        if app.calendarAvailable {
            SecLabel(text: t.t("set.calendar"), first: true, node: "sec.cal")
            HStack(spacing: 12) {
                Text(t.t("calm.title")).font(.system(size: 15)).foregroundStyle(pal.ink)
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { app.calendarMirrorOn },
                    set: { on in
                        // Отказали — спросить снова нельзя: ведём в настройки iPhone, там и выдаётся.
                        if on, app.calendarNeedsSettings { openSystemSettings() } else { app.setCalendarMirror(on) }
                    }))
                    .labelsHidden().tint(pal.brass)
                    .frame(height: 31)
                    .shotNode("calendar.toggle", text: app.calendarMirrorOn ? "on" : "off")
            }
            .padding(.horizontal, 24)
            .padding(.top, 15)
            .padding(.bottom, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
            // Открыли главу — узнать, где календарь лежит сейчас и какие учётные записи есть.
            .task { app.refreshCalendarSources() }
            SetNote(text: note(t), node: "note.cal")

            // Не завелось — список тоже виден: выбрать другую учётную запись и есть выход.
            if app.calendarMirrorOn || app.calendarFailed {
                SecLabel(text: t.t("calm.where"), node: "sec.where")
                ForEach(app.calendarSources) { source in
                    Button { app.setCalendarSource(source.id) } label: {
                        HStack(spacing: 12) {
                            Text(source.title).font(.system(size: 15)).foregroundStyle(pal.ink)
                            Spacer(minLength: 0)
                            if source.id == app.calendarSourceId { Icon("check", size: 18, line: 2).foregroundStyle(pal.brass) }
                        }
                        .frame(minHeight: 18)
                        .padding(.horizontal, 24)
                        .padding(.top, 15).padding(.bottom, 16)
                        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .shotNode("calendar.source", text: source.title)
                }
                SetNote(text: t.t("calm.whereNote"), node: "note.where")
            }

            ghostRows(t, pal)
        } else {
            SetItemRow(icon: nil, title: t.t("set.calendar"), value: "", chevron: false, dim: true)
        }
    }

    // MARK: - Другие календари (30.5)

    /// «Другие календари»: тумблер, под включённым — список календарей телефона с галочками. Чужие календари читаются
    /// только для показа (призраки): в Light Plan они не правятся, ни в какие данные и никуда не уходят. Права ещё нет —
    /// сначала объяснение, потом системный запрос (`app.ghostAsk`); отказали раньше — строка ведёт в настройки iPhone.
    @ViewBuilder
    private func ghostRows(_ t: Lexicon, _ pal: Palette) -> some View {
        HStack(spacing: 12) {
            Text(t.t("ghost.setTitle")).font(.system(size: 15)).foregroundStyle(pal.ink)
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { app.ghostsOn },
                set: { on in
                    if on, app.calendarNeedsSettings { openSystemSettings() } else { app.setGhosts(on) }
                }))
                .labelsHidden().tint(pal.brass)
                .frame(height: 31)
                .shotNode("ghost.toggle", text: app.ghostsOn ? "on" : "off")
        }
        .padding(.horizontal, 24)
        .padding(.top, 15)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
        SetNote(text: app.calendarNeedsSettings ? t.t("ghost.denied") : t.t("ghost.note"), node: "note.ghost")

        if app.ghostsOn {
            SecLabel(text: t.t("ghost.which"), node: "sec.ghost")
            if app.ghostChoices.isEmpty {
                SetNote(text: t.t("ghost.none"), node: "note.ghostNone")
            }
            ForEach(app.ghostChoices) { c in
                Button { app.setGhostCalendar(c.id, shown: !c.shown) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.calendar.title).font(.system(size: 15)).foregroundStyle(pal.ink)
                            if !c.calendar.sourceTitle.isEmpty {
                                Text(c.calendar.sourceTitle).font(.system(size: 12)).foregroundStyle(pal.ink5)
                            }
                        }
                        Spacer(minLength: 0)
                        if c.shown { Icon("check", size: 18, line: 2).foregroundStyle(pal.brass) }
                    }
                    .frame(minHeight: 18)
                    .padding(.horizontal, 24)
                    .padding(.top, 13).padding(.bottom, 14)
                    .overlay(alignment: .bottom) { Rectangle().fill(pal.hair2).frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(c.shown ? .isSelected : [])
                .shotNode("ghost.calendar", text: c.calendar.title + (c.shown ? " on" : " off"))
            }
            SetNote(text: t.t(GhostPolicy.ghostCalendarsDefault == .allPersonal ? "ghost.whichNote" : "ghost.whichNoteNone"),
                    node: "note.ghostWhich")
        }
    }

    /// Что сказать под тумблером: отказ в доступе и неудача важнее обычного пояснения.
    private func note(_ t: Lexicon) -> String {
        if app.calendarNeedsSettings { return t.t("calm.denied") }
        if app.calendarOffFailed { return t.t("calm.offFailed") }
        if app.calendarFailed { return t.t("calm.failed", ["where": app.calendarSourceTitle ?? ""]) }
        return t.t("calm.note")
    }

    private func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
    }
}
