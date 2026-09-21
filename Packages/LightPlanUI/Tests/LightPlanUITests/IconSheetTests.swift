import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import LightPlanUI

/// Контрольный лист рисуется в обеих темах. Для глаза — `ICON_SHEET_OUT=/папка`
/// сохраняет оба снимка (`icon_sheet_light.png`, `icon_sheet_dark.png`).
@MainActor
struct IconSheetTests {

    private func render(_ scheme: ColorScheme) throws -> CGImage {
        let bg = scheme == .dark ? Color(.sRGB, white: 0.08, opacity: 1) : Color(.sRGB, white: 0.98, opacity: 1)
        let ink = scheme == .dark ? Color(red: 0.89, green: 0.64, blue: 0.30) : Color(red: 0.55, green: 0.36, blue: 0.10)
        let view = IconSheet(columns: 8)
            .frame(width: 440)
            .tint(ink)
            .background(bg)
            .environment(\.colorScheme, scheme)
        let r = ImageRenderer(content: view)
        r.scale = 2
        return try #require(r.cgImage)
    }

    private func save(_ image: CGImage, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["ICON_SHEET_OUT"] else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    @Test func sheetRendersInBothThemes() throws {
        let light = try render(.light), dark = try render(.dark)
        save(light, "icon_sheet_light.png")
        save(dark, "icon_sheet_dark.png")
        #expect(light.width == 880 && light.height > 1000, "лист неожиданного размера: \(light.width)×\(light.height)")
        // Обе темы не пустые: в каждой есть и фон, и заметная доля цветного «чернила».
        for (name, img) in [("light", light), ("dark", dark)] {
            let g = IconPixelParityTests.gray(img)
            let bgLevel = Int(g.px[0])
            let differing = g.px.filter { abs(Int($0) - bgLevel) > 40 }.count
            #expect(differing > g.px.count / 60, "\(name): знаков на листе не видно (\(differing) из \(g.px.count) пикселей)")
        }
    }
}
