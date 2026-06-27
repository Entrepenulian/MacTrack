import AppKit
import SwiftUI

/// Fetches and caches real website favicons. Sources are tried in order
/// (DuckDuckGo → Google → the site's own /favicon.ico); the first usable image
/// wins. Results are cached in memory and on disk, so after the first sight of a
/// domain the icon is instant and works offline.
final class FaviconProvider {
    static let shared = FaviconProvider()

    private let memory = NSCache<NSString, NSImage>()
    private let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacTrack/Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        dir = base
    }

    private func diskURL(_ domain: String) -> URL {
        dir.appendingPathComponent(domain.replacingOccurrences(of: "/", with: "_") + ".png")
    }

    /// Synchronous cache lookup (memory, then disk). Nil if not fetched yet.
    func cached(_ domain: String) -> NSImage? {
        if let m = memory.object(forKey: domain as NSString) { return m }
        if let img = NSImage(contentsOf: diskURL(domain)) {
            memory.setObject(img, forKey: domain as NSString)
            return img
        }
        return nil
    }

    /// Fetches the favicon, caching it. Returns nil only if every source fails.
    func image(for domain: String) async -> NSImage? {
        if let c = cached(domain) { return c }

        let sources = [
            "https://icons.duckduckgo.com/ip3/\(domain).ico",
            "https://www.google.com/s2/favicons?sz=64&domain=\(domain)",
            "https://\(domain)/favicon.ico",
        ].compactMap { URL(string: $0) }

        for url in sources {
            guard let (data, response) = try? await URLSession.shared.data(from: url) else { continue }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data),
                  image.size.width >= 8 else { continue }

            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: diskURL(domain))
            }
            memory.setObject(image, forKey: domain as NSString)
            return image
        }
        return nil
    }
}

/// The real favicon for a domain, with a quiet globe placeholder while it loads.
/// Never shows a letter.
struct FaviconView: View {
    let domain: String
    var size: CGFloat = 22
    @State private var image: NSImage?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.27, style: .continuous) }

    var body: some View {
        Group {
            if let image {
                RawImage(nsImage: image, size: size)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.5))
            } else {
                shape
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        Image(systemName: "globe")
                            .font(.system(size: size * 0.5, weight: .regular))
                            .foregroundStyle(Theme.Ink.tertiary)
                    )
                    .frame(width: size, height: size)
            }
        }
        .task(id: domain) {
            // Per-account keys ("x.com/@handle") share their base domain's favicon.
            let d = SiteKey.base(domain)
            if let cached = FaviconProvider.shared.cached(d) { image = cached; return }
            image = await FaviconProvider.shared.image(for: d)
        }
    }
}
