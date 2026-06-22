import Foundation
import NetworkExtension
import SystemExtensions

/// App-side controller for the system-level blocker (Tier 3). It activates the
/// bundled Network Extension system extension and turns on the content filter.
///
/// This compiles and ships in the app, but it only *functions* once the app is
/// signed with the Network Extension entitlement, the extension target is built
/// and notarized, and the user approves it in System Settings. Until then,
/// `enable()` reports a failure status and the app-side blocker (hide/bounce)
/// remains the active layer. See SETUP_BLOCKING.md.
final class BlockFilterManager: NSObject, ObservableObject {
    /// Must match the system-extension target's bundle identifier.
    static let extensionIdentifier = "com.mactrack.MacTrack.NetworkFilter"

    @Published private(set) var statusText: String = "Off"
    @Published private(set) var isBusy = false

    /// Activate the system extension, then enable the content filter.
    func enable() {
        isBusy = true
        statusText = "Requesting…"
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    /// Turn the filter off and deactivate the extension.
    func disable() {
        let manager = NEFilterManager.shared()
        manager.isEnabled = false
        manager.saveToPreferences { _ in }
        statusText = "Off"
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: Self.extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func refresh() {
        NEFilterManager.shared().loadFromPreferences { [weak self] error in
            let manager = NEFilterManager.shared()
            let on = error == nil && manager.isEnabled && manager.providerConfiguration != nil
            self?.statusText = on ? "On" : "Off"
        }
    }

    private func enableContentFilter() {
        let manager = NEFilterManager.shared()
        manager.loadFromPreferences { [weak self] _ in
            if manager.providerConfiguration == nil {
                let config = NEFilterProviderConfiguration()
                config.filterSockets = true
                config.filterPackets = false
                manager.providerConfiguration = config
                manager.localizedDescription = "MacTrack"
            }
            manager.isEnabled = true
            manager.saveToPreferences { error in
                self?.statusText = (error == nil) ? "On" : "Filter error"
            }
        }
    }
}

extension BlockFilterManager: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        statusText = "Approve in System Settings"
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        isBusy = false
        if result == .completed {
            enableContentFilter()
        } else {
            statusText = "Reboot to finish install"
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        isBusy = false
        statusText = "Failed: \(error.localizedDescription)"
    }
}
