import Foundation
import Darwin

@MainActor
final class RemoteMacScreenModule: NotchcastModule {
    let preferences: NotchcastPreferences
    let open: (URL) -> Void
    let post: (String) -> Void
    let changed: () -> Void

    init(preferences: NotchcastPreferences, open: @escaping (URL) -> Void,
         post: @escaping (String) -> Void, changed: @escaping () -> Void = {}) {
        self.preferences = preferences
        self.open = open
        self.post = post
        self.changed = changed
    }

    func start() { changed() }
    func stop() { changed() }

    func openScreen() {
        guard preferences.isOn(.remoteMacScreen) else { return }
        guard let url = Self.url(address: preferences.remoteMacAddress) else {
            post(String(localized: "Set the remote Mac address in Settings"))
            return
        }
        open(url)
    }

    static func url(address: String) -> URL? {
        guard MachSSH.isValid(address) else { return nil }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }), let last = parts.last else { return nil }
        let host = String(last)
        if host.contains(":") {
            var bytes = in6_addr()
            guard inet_pton(AF_INET6, host, &bytes) == 1 else { return nil }
        }
        var components = URLComponents()
        components.scheme = "vnc"
        components.host = host.contains(":") ? "[\(host)]" : host
        if parts.count == 2 { components.user = String(parts[0]) }
        return components.url
    }
}
