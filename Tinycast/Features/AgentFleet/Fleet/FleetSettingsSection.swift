import SwiftUI

struct FleetSettingsSection: View {
    private static let defaults = UserDefaults(
        suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast.fleet")!
    @AppStorage("remoteEnvironmentID", store: defaults) private var remoteEnvironmentID = ""
    @AppStorage("localEnvironmentID", store: defaults) private var localEnvironmentID = ""
    @AppStorage("workspacePath", store: defaults) private var workspacePath = ""

    static func destinations(localMachine: String, remoteMachine: String) -> [FleetSnapshot.Destination] {
        let path = defaults.string(forKey: "workspacePath").flatMap { $0.isEmpty ? nil : $0 }
        return [
            .init(machine: localMachine, environmentID: defaults.string(forKey: "localEnvironmentID") ?? "",
                  workspacePath: path, route: .local),
            .init(machine: remoteMachine, environmentID: defaults.string(forKey: "remoteEnvironmentID") ?? "",
                  workspacePath: path, route: .linked),
        ]
    }

    var body: some View {
        Section {
            TextField("Remote environment ID", text: $remoteEnvironmentID)
            TextField("Local environment ID", text: $localEnvironmentID)
            TextField("Optional workspace path", text: $workspacePath)
        } header: {
            Text("Fleet panel")
        }
    }
}
