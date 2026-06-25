import SwiftUI
import CoreText

/// Bundled-font access for the Focus Guard quote card. Fonts ship as variable
/// TTFs, so we drive the `wght` axis ourselves to get the exact weight rather
/// than the file's default instance.
enum AppFont {

    private static var didRegister = false

    /// Register the bundled TTFs with the process. Idempotent; safe to call early.
    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        var urls = Set<URL>()
        for sub in [nil, "Fonts"] as [String?] {
            urls.formUnion(Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: sub) ?? [])
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static let wghtAxis = 0x77676874   // 'wght'

    /// Any registered family at an explicit weight, optionally italic. Weight is
    /// applied through the variable font's `wght` axis so it's honoured exactly.
    static func custom(_ family: String, _ size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> Font {
        var attrs: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontVariationAttribute: [wghtAxis: weight],
        ]
        if italic {
            attrs[kCTFontTraitsAttribute] = [kCTFontSymbolicTrait: CTFontSymbolicTraits.traitItalic.rawValue]
        }
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(desc, size, nil))
    }
}
