import AppKit
import SwiftUI

/// Pulls a representative brand color from an app icon or website favicon — the
/// dominant *vivid* hue, not the white/black background — and tunes it so it reads
/// well as the detail bar chart's color without ever looking out of place. Results
/// are cached per entry; falls back to the brand amber when there's no clear color
/// (e.g. a grayscale icon) or the image hasn't loaded.
enum IconColor {
    @MainActor private static var cache: [String: Color] = [:]

    @MainActor
    static func resolve(for entry: UsageEntry) async -> Color {
        if let cached = cache[entry.id] { return cached }
        var image: NSImage?
        switch entry.kind {
        case .app(let bundleID):
            image = IconProvider.shared.icon(for: bundleID)
        case .site(let domain):
            let d = SiteKey.base(domain)
            if let c = FaviconProvider.shared.cached(d) { image = c }
            else { image = await FaviconProvider.shared.image(for: d) }
        }
        let color = image.flatMap(dominant) ?? Theme.focus
        cache[entry.id] = color
        return color
    }

    /// The dominant vivid color of an image, normalized for the dark UI.
    static func dominant(_ image: NSImage) -> Color? {
        guard let cg = RawImage.rasterize(image, points: 32, scale: 1) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Saturation-weighted histogram over 12 hue buckets. Skip transparent,
        // near-white, near-black and washed-out pixels — those are backgrounds and
        // edges, not the brand color. Averaging the winning hue bucket gives a clean
        // representative color instead of a single noisy pixel.
        var buckets = [(w: Double, r: Double, g: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        var vivid = 0.0
        for i in stride(from: 0, to: data.count, by: 4) {
            if Double(data[i + 3]) / 255 < 0.5 { continue }
            let r = Double(data[i]) / 255, g = Double(data[i + 1]) / 255, b = Double(data[i + 2]) / 255
            let (hue, sat, bri) = hsb(r, g, b)
            if sat < 0.2 || bri < 0.12 || bri > 0.96 { continue }
            // Favor saturated, mid-bright pixels (the logo), not pale tints.
            let centered: Double = 1.0 - min(1.0, abs(bri - 0.6) / 0.5)
            let weight: Double = sat * (0.5 + 0.5 * centered)
            let k = min(11, Int(hue * 12))
            buckets[k].w += weight
            buckets[k].r += r * weight; buckets[k].g += g * weight; buckets[k].b += b * weight
            vivid += weight
        }
        guard vivid > 0, let best = buckets.max(by: { $0.w < $1.w }), best.w > 0 else { return nil }
        return normalized(best.r / best.w, best.g / best.w, best.b / best.w)
    }

    /// Keep the hue, gently floor saturation/brightness so any brand color stays
    /// legible on the dark popover and never reads as a muddy or blown-out outlier.
    private static func normalized(_ r: Double, _ g: Double, _ b: Double) -> Color {
        let (h, s0, v0) = hsb(r, g, b)
        let s = max(0.5, min(0.95, s0))
        let v = max(0.62, min(0.92, v0))
        let (nr, ng, nb) = rgb(h, s, v)
        return Color(.sRGB, red: nr, green: ng, blue: nb)
    }

    // MARK: RGB ↔ HSB on doubles in [0, 1]

    private static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d != 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    private static func rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        if s == 0 { return (v, v, v) }
        let h6 = h * 6
        let i = Int(h6) % 6
        let f = h6 - Double(Int(h6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
