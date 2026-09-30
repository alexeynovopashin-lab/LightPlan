import SwiftUI
import LightPlanCore
import LightPlanDomain

// MARK: - Полка жанра (`#mbShelfOverlay`, итерация 28, шаг 5а)

/// Только когда в жанре больше одной папки: заголовок жанра, «N папок · M кадров»,
/// плитки папок и «Новая папка» последней. Тап по папке — экран папки (шаг 5б).
struct MoodboardShelf: View {
    @Bindable var app: AppModel
    let genre: String
    @Environment(\.colorScheme) private var scheme
    @State private var asking = false
    @State private var name = ""

    private var t: Lexicon { app.lexicon }

    var body: some View {
        let pal = Palette(scheme)
        let lib = app.mbLibrary()
        let shelf = Moodboard.shelf(lib, genre: genre)
        let genreName = app.mbGenreName(genre)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverlayBack(title: t.t("set.moodboards"), node: "mb.shelfBack") {
                    withAnimation(overlaySlide) { app.closeMbShelf() }
                }
                .padding(.top, 6)
                Text(genreName).font(webFont(22, 650)).tracking(-0.5).foregroundStyle(pal.ink)
                    .padding(.top, 10).shotNode("mb.shelfTitle", text: genreName)
                Text(t.count("unit.folder", shelf.folders.count) + " · " + t.count("unit.frame", shelf.frameCount))
                    .font(webFont(14)).foregroundStyle(pal.ink4).padding(.top, 6)
                    .shotNode("mb.shelfSub")
                MbTileGrid {
                    ForEach(Array(shelf.folders.enumerated()), id: \.element.id) { i, b in
                        let n = b.items.filter { id in lib.shots.contains { $0.id == id } }.count
                        MbTile(boardId: b.id, genre: genre, count: n,
                               title: Moodboard.title(of: b, genreName: genreName),
                               sub: t.count("unit.frame", n), node: "mb.folder.\(i)") {}
                    }
                    MbAddTile(title: t.t("mb.newFolder"), node: "mb.shelfAdd") { name = ""; asking = true }
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 34)
        }
        .background(pal.surface.ignoresSafeArea())
        // Имя папки спрашивается сразу: две безымянные папки в одном жанре не отличить (веб `mbNewFolder`).
        .alert(t.t("mb.newFolderAsk"), isPresented: $asking) {
            TextField("", text: $name)
            Button(t.t("ask.cancel"), role: .cancel) {}
            Button(t.t("mb.pickDone")) { app.mbAddFolder(genre: genre, name: name) }
        }
        .shotNode("mb.shelf", text: "\(shelf.folders.count)")
    }
}
