import SwiftUI

struct URLCleanerSettingsSection: View {
    @Bindable var module: URLCleanerModule

    var body: some View {
        Section {
            TextField("Custom parameters", text: list(\.custom))
            TextField("Disabled parameters", text: list(\.disabled))
            TextField("Per-site parameters", text: Binding(
                get: { module.rules.perSite.sorted { $0.key < $1.key }
                    .map { $0.key + "=" + $0.value.joined(separator: ",") }.joined(separator: ";") },
                set: { text in
                    var sites: [String: [String]] = [:]
                    for row in text.split(separator: ";") {
                        let parts = row.split(separator: "=", maxSplits: 1)
                        if parts.count == 2 {
                            sites[String(parts[0]).lowercased()] = parts[1].split(separator: ",").map(String.init)
                        }
                    }
                    module.rules.perSite = sites
                }))
            if let result = module.lastClean {
                LabeledContent("Last removed parameters", value: result.removed.joined(separator: ", "))
            }
        } header: {
            Text("URL cleaner")
        }
    }

    private func list(_ keyPath: WritableKeyPath<URLCleanerPolicy.Rules, [String]>) -> Binding<String> {
        Binding(get: { module.rules[keyPath: keyPath].joined(separator: ",") }, set: {
            module.rules[keyPath: keyPath] = $0.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }
        })
    }
}
