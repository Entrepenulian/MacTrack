import SwiftUI

/// Owns the long-lived services and keeps them alive for the app's lifetime.
/// Injecting store/monitor/loginItem as separate environment objects (rather
/// than reaching through this container) ensures SwiftUI observes each one's
/// changes directly.
@MainActor
final class AppModel: ObservableObject {
    let store: UsageStore
    let blocks: BlockController
    let focusGuard: FocusGuard
    let monitor: ActivityMonitor
    let loginItem: LoginItem
    let filter = BlockFilterManager()

    init() {
        AppFont.registerBundledFonts()
        let database = try? DatabaseStore()        // one shared connection
        let store = UsageStore(database: database)
        self.store = store
        let blocks = BlockController(db: database)
        self.blocks = blocks
        let focusGuard = FocusGuard()
        self.focusGuard = focusGuard
        self.monitor = ActivityMonitor(store: store, blocks: blocks, focusGuard: focusGuard)
        self.loginItem = LoginItem()

        // Dev-only: with MACTRACK_TEST_BLUR=1 set, fire the blur a moment after
        // launch so the overlay can be previewed/screenshotted. In this mode the
        // sampler is NOT started, so this throwaway instance never tracks or
        // writes — it can't disturb a real running copy. No effect otherwise.
        let testBlur = ProcessInfo.processInfo.environment["MACTRACK_TEST_BLUR"] == "1"

        if !testBlur { monitor.start() }

        if testBlur {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [focusGuard] in
                focusGuard.test()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [store, monitor] _ in
            MainActor.assumeIsolated {
                monitor.stop()
                store.saveNow()
            }
        }
    }
}

@main
struct MacTrackApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuRootView()
                .environmentObject(model.store)
                .environmentObject(model.monitor)
                .environmentObject(model.loginItem)
                .environmentObject(model.blocks)
                .environmentObject(model.filter)
                .environmentObject(model.focusGuard)
        } label: {
            MenuBarLabel()
                .environmentObject(model.store)
                .environmentObject(model.monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The status-bar label: a quiet glyph plus today's time for whatever you're on
/// right now — the current website if you're browsing, otherwise the current app.
/// Compact (minute resolution) so the menu bar doesn't tick every second.
struct MenuBarLabel: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var monitor: ActivityMonitor

    var body: some View {
        let seconds = store.focusSeconds(domain: monitor.currentDomain, bundleID: monitor.currentBundleID)
        HStack(spacing: 4) {
            // A status item renders exactly one leading image, so the project's
            // color dot takes the hourglass's slot while a project is active.
            // `.original` keeps the color through the menu bar's template pass.
            if let p = store.activeProject {
                Image(nsImage: MenuBarDot.image(for: p.color))
                    .renderingMode(.original)
            } else {
                Image(systemName: "hourglass")
            }
            if seconds >= 1 {
                Text(Format.duration(seconds)).monospacedDigit()
            }
        }
    }
}

/// The status item's leading image: a filled dot in the active project's color.
/// Rendered once per color and cached, because the label re-evaluates as the
/// tracked time changes.
@MainActor
enum MenuBarDot {
    private static var cache: [String: NSImage] = [:]

    static func image(for color: Color) -> NSImage {
        let key = hexKey(color)
        if let cached = cache[key] { return cached }

        // A 3 pt transparent tail keeps the dot off the time text — the status item
        // packs its image and title directly together.
        let renderer = ImageRenderer(
            content: HStack(spacing: 0) {
                Circle().fill(color).frame(width: 7, height: 7)
                Color.clear.frame(width: 3, height: 7)
            }
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 7, height: 7))
        image.isTemplate = false      // keep the project color in the menu bar
        cache[key] = image
        return image
    }

    private static func hexKey(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "%02X%02X%02X",
                      Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()),
                      Int((ns.blueComponent * 255).rounded()))
    }
}
