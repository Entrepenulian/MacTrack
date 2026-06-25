import SwiftUI
import CoreText

/// Bundled-font access. The Focus Guard quote is set in Cormorant Garamond, a
/// classic high-contrast garalde that reads like a printed epigraph rather than
/// a system label.
///
/// The file ships as a single variable font that defaults to Light, so we drive
/// the `wght` axis ourselves to pull real SemiBold weight out of it instead of
/// getting the thin default.
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

    /// Cormorant Garamond at an explicit optical weight (300–700), optionally
    /// italic. Built straight from the variable font so the weight is honoured.
    static func cormorant(_ size: CGFloat, weight: CGFloat = 600, italic: Bool = false) -> Font {
        var attrs: [CFString: Any] = [
            kCTFontFamilyNameAttribute: "Cormorant Garamond",
            kCTFontVariationAttribute: [wghtAxis: weight],
        ]
        if italic {
            attrs[kCTFontTraitsAttribute] = [kCTFontSymbolicTrait: CTFontSymbolicTraits.traitItalic.rawValue]
        }
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        let ct = CTFontCreateWithFontDescriptor(desc, size, nil)
        return Font(ct)
    }
}
