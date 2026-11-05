import SwiftUI

struct DictationCleanupEndpointSettingRow: View {
    let module: DictationCleanupModule

    var body: some View {
        TextField(text: Binding(get: { module.settings.baseURL }, set: {
            var updated = module.settings
            updated.baseURL = $0
            module.save(updated)
        })) {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Cleanup endpoint")
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct DictationCleanupEffortSettingRow: View {
    let module: DictationCleanupModule

    var body: some View {
        Picker(selection: Binding(get: { module.settings.effort }, set: {
            var updated = module.settings
            updated.effort = $0
            module.save(updated)
        })) {
            Text("Low").tag(DictationCleanupSettings.Effort.low)
            Text("Medium").tag(DictationCleanupSettings.Effort.medium)
            Text("High").tag(DictationCleanupSettings.Effort.high)
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Cleanup effort")
        }
    }
}

struct DictationCleanupPromptSettingRow: View {
    let module: DictationCleanupModule

    var body: some View {
        TextField(text: Binding(get: { module.settings.promptAddition }, set: {
            var updated = module.settings
            updated.promptAddition = $0
            module.save(updated)
        }), axis: .vertical) {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Cleanup prompt addition")
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct DictationCleanupVocabularySettingRow: View {
    let module: DictationCleanupModule
    @State private var vocabularyText = ""

    var body: some View {
        TextField(text: vocabulary, axis: .vertical) {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Cleanup vocabulary")
            Text("One spelling per line; separate misheard forms with |.")
        }
        .textFieldStyle(.roundedBorder)
        .onAppear {
            vocabularyText = module.settings.vocabulary.map {
                ([$0.spelling] + $0.misheardForms).joined(separator: " | ")
            }.joined(separator: "\n")
        }
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

struct DictationCleanupAPIKeySettingRow: View {
    let module: DictationCleanupModule
    @State private var key = ""
    @State private var keyLoaded = false

    var body: some View {
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
}
