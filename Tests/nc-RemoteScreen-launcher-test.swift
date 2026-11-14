// notchcast-sources: Tinycast/Features/RemoteScreen/Model/*.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/Service/RemoteScreenLauncher.swift
import AppKit

@MainActor private final class Workspace: RemoteScreenWorkspace {
    enum Failure: Error { case launch }
    var preferredInstalled = true
    var fails = false
    var opened: [URL] = []
    func urlForApplication(withBundleIdentifier bundleID: String) -> URL? {
        if bundleID == RemoteScreenState.Client.preferred.bundleID && !preferredInstalled { return nil }
        return URL(fileURLWithPath: "/Applications/\(bundleID).app")
    }
    func openRemoteScreen(_ url: URL, application: URL) async throws {
        if fails { throw Failure.launch }
        opened.append(application)
    }
}

@main struct ScreenLauncherTest {
    @MainActor static func main() async throws {
        let workspace = Workspace()
        let launcher = RemoteScreenLauncher(workspace: workspace)
        let url = URL(string: "vnc://peer.local")!
        for installed in [true, false] {
            workspace.preferredInstalled = installed
            precondition(launcher.preferredClientInstalled == installed)
            try await launcher.open(url, client: installed ? .preferred : .apple)
            let bundle = installed ? "io.nekohasekai.screensharing" : "com.apple.ScreenSharing"
            precondition(workspace.opened.last == URL(fileURLWithPath: "/Applications/\(bundle).app"))
        }
        workspace.fails = true
        do { try await launcher.open(url, client: .apple); fatalError("Launch error swallowed") }
        catch Workspace.Failure.launch {}
        print("PASS installed client, Apple fallback, launch error propagation")
    }
}
