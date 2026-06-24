import NetworkExtension
import Network

/// The system-level content filter (Tier 3). Runs as a Network Extension system
/// extension — outside the app's process, enforced by the OS — so it keeps
/// filtering even if MacTrack is quit, and it can't be bypassed by DNS-over-HTTPS
/// because it decides per network flow by hostname.
///
/// It reads the blocked-domain list from the shared App Group container that the
/// app writes (see BlockController.syncToAppGroup). Drops any flow whose host
/// matches a blocked domain or a subdomain of it.
///
/// NOTE: This file lives OUTSIDE the `MacTrack/` sources folder on purpose, so it
/// is not compiled into the unsigned app build. Add it to a dedicated system
/// extension target as described in SETUP_BLOCKING.md.
final class FilterDataProvider: NEFilterDataProvider {
    private let appGroup = "group.com.julianhahne.MacTrack"
    private var blocked: Set<String> = []

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        loadBlocked()
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        loadBlocked()   // cheap re-read so newly-added blocks take effect immediately
        guard let host = host(for: flow) else { return .allow() }
        for domain in blocked where host == domain || host.hasSuffix("." + domain) {
            return .drop()
        }
        return .allow()
    }

    private func host(for flow: NEFilterFlow) -> String? {
        if let url = flow.url, let h = url.host { return h.lowercased() }
        guard let socket = flow as? NEFilterSocketFlow else { return nil }
        if #available(macOS 15.0, *), let endpoint = socket.remoteFlowEndpoint,
           case let .hostPort(host, _) = endpoint {
            if case let .name(name, _) = host { return name.lowercased() }
            return nil   // raw IP — no hostname to match
        }
        if let endpoint = socket.remoteEndpoint as? NWHostEndpoint {
            return endpoint.hostname.lowercased()
        }
        return nil
    }

    private func loadBlocked() {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return }
        let url = dir.appendingPathComponent("blocked-domains.json")
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return }
        blocked = Set(list.map { $0.lowercased() })
    }
}
