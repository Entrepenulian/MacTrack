import ServiceManagement
import SwiftUI

/// Wraps SMAppService so the app can launch at login. Reads the live system
/// state rather than a stored flag, so the toggle never lies.
@MainActor
final class LoginItem: ObservableObject {
    @Published var isEnabled: Bool = false

    init() { refresh() }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("MacTrack login item error: \(error.localizedDescription)")
        }
        refresh()
    }
}
