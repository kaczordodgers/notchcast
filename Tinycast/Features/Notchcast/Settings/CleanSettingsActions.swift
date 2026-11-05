import AppKit

enum CleanSettingsActions {
    @MainActor static func scan(_ feature: NotchcastFeature, coordinator: CleanCoordinator) {
        guard !coordinator.busy.contains(feature), NotchcastPreferences.shared.isEnabled(feature) else { return }
        guard feature == .cleanDisk || feature == .cleanPurge else {
            coordinator.scan(feature)
            return
        }
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = feature == .cleanPurge
        picker.canCreateDirectories = false
        picker.begin { response in
            guard response == .OK, NotchcastPreferences.shared.isEnabled(feature) else { return }
            coordinator.scan(feature, roots: picker.urls)
        }
    }
}
