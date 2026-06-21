import SwiftUI

/// Owns the long-lived services and keeps them alive for the app's lifetime.
/// Injecting store/monitor/loginItem as separate environment objects (rather
/// than reaching through this container) ensures SwiftUI observes each one's
/// changes directly.
@MainActor
final class AppModel: ObservableObject {
    let store: UsageStore
    let monitor: ActivityMonitor
    let loginItem: LoginItem

    init() {
        let store = UsageStore()
        self.store = store
        self.monitor = ActivityMonitor(store: store)
        self.loginItem = LoginItem()

        monitor.start()

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
