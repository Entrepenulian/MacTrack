import AppKit
import SwiftUI

/// Resolves and caches real application icons by bundle identifier. Icons are
/// read live from the installed apps, never stored.
@MainActor
final class IconProvider {
    static let shared = IconProvider()
    private var cache: [String: NSImage] = [:]

    func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        // Prefer the real .icns artwork — NSWorkspace.icon(forFile:) returns the
        // system's accent-tinted variant on macOS 26, not the true colors.
        let image = trueColorIcon(appURL: appURL) ?? NSWorkspace.shared.icon(forFile: appURL.path)
        cache[bundleID] = image
        return image
    }

    private func trueColorIcon(appURL: URL) -> NSImage? {
        guard let bundle = Bundle(url: appURL) else { return nil }
        let resources = appURL.appendingPathComponent("Contents/Resources")

        var candidates: [String] = []
        if let name = (bundle.infoDictionary?["CFBundleIconFile"] as? String)
            ?? (bundle.infoDictionary?["CFBundleIconName"] as? String) {
            candidates.append(name.hasSuffix(".icns") ? name : name + ".icns")
        }
        candidates.append("AppIcon.icns")
        if let all = try? FileManager.default.contentsOfDirectory(atPath: resources.path) {
            candidates.append(contentsOf: all.filter { $0.hasSuffix(".icns") })
        }

        for name in candidates {
            let url = resources.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path), let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return nil
    }
}

/// Renders an NSImage by rasterizing it into an explicit RGBA bitmap, then
/// drawing that via `Image(decorative:)`. This captures the real pixels — app
/// icons stop being treated as accent-tinted templates and keep true colors.
struct RawImage: View {
    let nsImage: NSImage
    var size: CGFloat

    var body: some View {
        if let cg = Self.rasterize(nsImage, points: size) {
            Image(decorative: cg, scale: 2)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        }
    }

    static func rasterize(_ image: NSImage, points: CGFloat, scale: CGFloat = 2) -> CGImage? {
        let px = Int(points * scale)
        guard px > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: points, height: points)

        let drawImage = (image.copy() as? NSImage) ?? image
        drawImage.isTemplate = false

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawImage.draw(in: NSRect(x: 0, y: 0, width: points, height: points),
                       from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}

/// The real application icon, in full color. Falls back to a neutral glyph (not
/// a letter) only if the app can't be located on disk.
struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 22

    var body: some View {
        if let icon = IconProvider.shared.icon(for: bundleID) {
            RawImage(nsImage: icon, size: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    Image(systemName: "app.dashed")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(Theme.Ink.tertiary)
                )
                .frame(width: size, height: size)
        }
    }
}
