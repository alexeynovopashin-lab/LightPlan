import Foundation
import LightPlanCore
import LightPlanDomain
import LightPlanData

// MARK: - Прямые ссылки на фото в мудборде (итерация 28н.1)
//
// Адрес вида `https://…/photo.jpg` ложится в папку плиткой-ссылкой сразу, картинка догоняет и сохраняется на телефоне
// (`attachments/`), как у пина Pinterest. Путь: напрямую, а при «Авто» и неудаче — через нашу функцию (`?pic=`);
// «Только напрямую» (28л.6) наш сервер не трогает и говорит об этом. Адрес без расширения (`…/photo-123?w=800`) проверяется
// тихо, напрямую: если там страница, плитка остаётся обычной ссылкой и никаких надписей. Не вышло — плитка остаётся
// плиткой, под кнопками честная строка с «Повторить», картинка не придумывается.

extension AppModel {

    func imageLinkText(_ f: ImageLinkFailure) -> String {
        switch f {
        case .offline: lexicon.t("pin.offline")
        case .unreachable: lexicon.t("img.unreachable")
        case .notFound: lexicon.t("img.notFound")
        case .notImage: lexicon.t("img.notImage")
        case .tooLarge: lexicon.t("img.tooLarge")
        case .badLink: lexicon.t("img.badLink")
        case .busy: lexicon.t("pin.busy")
        case .serverOff: lexicon.t("img.serverOff")
        }
    }

    /// Плитка-ссылка уже в папке; картинка догоняет. `quiet` — адрес без расширения: ошибки молчат, страница остаётся ссылкой.
    func startImagePreview(frame: String, link: String, quiet: Bool) {
        guard let reader = imageLinks else { return }
        if case .image(_, let r)? = mb.pinNote, r == frame { mb.pinNote = nil }
        Task { [weak self] in
            do {
                let data = try await reader.picture(at: link, viaServer: !quiet)
                self?.attachImagePicture(data, to: frame, quiet: quiet)
            } catch is CancellationError {
            } catch {
                if quiet { return }
                self?.mb.pinNote = .image((error as? ImageLinkFailure) ?? .unreachable, retryFrame: frame)
            }
        }
    }

    private func attachImagePicture(_ data: Data, to frame: String, quiet: Bool) {
        guard let images = refImages, let size = RefImageStore.pixelSize(of: data) else {
            if !quiet { mb.pinNote = .image(.notImage, retryFrame: frame) }
            return
        }
        let im = UUID().uuidString.lowercased()
        guard images.save(data, as: im) else { if !quiet { mb.pinNote = .image(.notImage, retryFrame: frame) }; return }
        // Кадр могли убрать, пока шла загрузка, или картинка уже догнала — тогда файл не нужен.
        let ok = mbEdit { lib, now in lib.attachImage(im: im, w: size.w, h: size.h, toFrame: frame, now: now) }
        if !ok { images.delete(im) }
        else if case .image(_, let r)? = mb.pinNote, r == frame { mb.pinNote = nil }
    }

    /// «Повторить» под строкой про картинку по прямой ссылке.
    func retryImageNote() {
        guard case .image(_, let frame)? = mb.pinNote else { return }
        guard let frame, let url = mbLibrary().shot(frame)?.url else { mb.pinNote = nil; return }
        startImagePreview(frame: frame, link: url, quiet: false)
    }
}
