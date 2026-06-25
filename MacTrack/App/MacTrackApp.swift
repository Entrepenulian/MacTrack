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

        monitor.start()

        // Dev-only: with MACTRACK_TEST_BLUR=1 set, fire the Focus Guard blur a
        // moment after launch so the overlay design can be previewed/screenshotted
        // without driving the menu UI. No effect for normal users.
        if ProcessInfo.processInfo.environment["MACTRACK_TEST_BLUR"] == "1" {
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
            Image(systemName: "hourglass")
            if seconds >= 1 {
                Text(Format.duration(seconds)).monospacedDigit()
            }
        }
    }
}
