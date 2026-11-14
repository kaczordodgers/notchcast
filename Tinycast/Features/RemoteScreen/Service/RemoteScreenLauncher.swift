import AppKit

@MainActor protocol RemoteScreenWorkspace {
    func urlForApplication(withBundleIdentifier bundleID: String) -> URL?
    func openRemoteScreen(_ url: URL, application: URL) async throws
}

extension NSWorkspace: RemoteScreenWorkspace {
    func openRemoteScreen(_ url: URL, application: URL) async throws {
        _ = try await open([url], withApplicationAt: application, configuration: OpenConfiguration())
    }
}

@MainActor struct RemoteScreenLauncher {
    var workspace: any RemoteScreenWorkspace = NSWorkspace.shared

    var preferredClientInstalled: Bool {
        workspace.urlForApplication(withBundleIdentifier: RemoteScreenState.Client.preferred.bundleID) != nil
    }

    func open(_ url: URL, client: RemoteScreenState.Client) async throws {
        guard let application = workspace.urlForApplication(withBundleIdentifier: client.bundleID)
        else { throw RemoteScreenRequest.Failure.unavailable }
        try await workspace.openRemoteScreen(url, application: application)
    }
}
