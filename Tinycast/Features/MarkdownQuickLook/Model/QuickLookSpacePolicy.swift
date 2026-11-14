import Foundation

enum QuickLookSpacePolicy {
    static func acceptsInput(currentPanel: Bool, fileSearch: Bool, menuOpen: Bool,
                             editingField: Bool, controlListOpen: Bool) -> Bool {
        currentPanel && fileSearch && !menuOpen && !editingField && !controlListOpen
    }

    static func file(
        _ url: URL?, enabled: Bool, selectedByArrowKeys: Bool,
        hasModifiers: Bool, isRepeat: Bool, isComposing: Bool
    ) -> URL? {
        guard enabled, selectedByArrowKeys, !hasModifiers, !isRepeat, !isComposing,
            let url, url.isFileURL
        else { return nil }
        return url
    }
}
