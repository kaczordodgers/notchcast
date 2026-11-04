import SwiftUI

struct DictationCleanupSettingsSection: View {
    let module: DictationCleanupModule
    private let preferences = NotchcastPreferences.shared
    @State private var key = ""
    @State private var keyLoaded = false
    @State private var vocabularyText = ""

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.dictationCleanup) },
            set: { preferences.set(.dictationCleanup, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, "AI cleanup")
                Text(NotchcastFeature.dictationCleanup.subtitle)
            }
        Group {
            TextField(text: setting(\.baseURL)) {
                SettingsRowTitle(.notchcastCaptureAndDictation, "Cleanup endpoint")
            }
            Picker(selection: setting(\.effort)) {
                Text("Low").tag(DictationCleanupSettings.Effort.low)
                Text("Medium").tag(DictationCleanupSettings.Effort.medium)
                Text("High").tag(DictationCleanupSettings.Effort.high)
            } label: {
                SettingsRowTitle(.notchcastCaptureAndDictation, "Cleanup effort")
            }
            TextField(text: setting(\.promptAddition), axis: .vertical) {
                SettingsRowTitle(.notchcastCaptureAndDictation, "Cleanup prompt addition")
            }
            TextField(text: vocabulary, axis: .vertical) {
                SettingsRowTitle(.notchcastCaptureAndDictation, "Cleanup vocabulary")
                Text("One spelling per line; separate misheard forms with |.")
            }
            .onAppear {
                vocabularyText = module.settings.vocabulary.map {
                    ([$0.spelling] + $0.misheardForms).joined(separator: " | ")
                }.joined(separator: "\n")
            }
            LabeledContent {
                SecureField("API key", text: $key)
                    .onSubmit { if keyLoaded { module.saveAPIKey(key) } }
                Button("Save") { module.saveAPIKey(key) }
                    .disabled(!keyLoaded)
            } label: {
                SettingsRowTitle(.notchcastCaptureAndDictation, "Cleanup API key")
            }
            .onAppear {
                if let loaded = module.apiKey() {
                    key = loaded
                    keyLoaded = true
                }
            }
            .onDisappear { key = ""; keyLoaded = false }
        }
        .settingsEnabled(preferences.isOn(.dictationCleanup))
    }

    private func setting<Value>(_ path: WritableKeyPath<DictationCleanupSettings, Value>) -> Binding<Value> {
        Binding(get: { module.settings[keyPath: path] }, set: {
            var updated = module.settings
            updated[keyPath: path] = $0
            module.save(updated)
        })
    }

    private var vocabulary: Binding<String> {
        Binding(get: { vocabularyText }, set: { text in
            vocabularyText = text
            var updated = module.settings
            updated.vocabulary = DictationCleanupSettings.vocabulary(from: text)
            module.save(updated)
        })
    }
}
