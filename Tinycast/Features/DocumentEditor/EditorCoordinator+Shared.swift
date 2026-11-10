import Foundation

extension EditorCoordinator {
    static let shared = EditorCoordinator(
        preferences: .shared,
        editorPreferences: EditorPreferences(
            defaults: UserDefaults(suiteName: NotchcastIdentity.current.suiteName(suffix: ".editor"))!))
}
