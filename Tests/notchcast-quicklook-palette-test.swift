// notchcast-sources: Tinycast/Features/MarkdownQuickLook/QuickLookSpace+Palette.swift
// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Service/QuickLookCoordinator.swift
// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Service/QuickLookSpaceInput.swift
// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Model/QuickLookRequest.swift
// notchcast-sources: Tinycast/Features/MarkdownQuickLook/Model/QuickLookSpacePolicy.swift
import AppKit
import Carbon.HIToolbox

@MainActor protocol NotchcastModule {}
@MainActor final class NotchcastPreferences {
    static var enabled = true
    enum Feature { case quickLookSpace }
    func isOn(_ feature: Feature) -> Bool { Self.enabled }
}
@MainActor final class QuickLookSystemPresenter {
    var shown: QuickLookRequest?
    func show(_ request: QuickLookRequest) { shown = request }
    func close() {}
}
extension QuickLookCoordinator {
    static let shared = QuickLookCoordinator(preferences: NotchcastPreferences())
}
@MainActor final class PaletteState {
    enum Mode { case fileSearch, launcher }
    var mode = Mode.fileSearch
    var menuOpen = false
    var isEditingField = false
    var isControlListOpen = false
    var resetToken = UUID()
    var selection = 0
    var isComposing = false
}
@MainActor final class PalettePanel: NSPanel {
    var paletteState = AppCore.shared.palette
}
@MainActor final class AppCore {
    static let shared = AppCore()
    let palette = PaletteState()
    var fileSearch = Search()
    let paletteCoordinator = Coordinator()
    struct Search {
        struct Row { let url: URL }
        var results = [Row(url: URL(fileURLWithPath: "/tmp/example.md"))]
    }
    final class Coordinator {
        var dismissed = false
        func hidePalette(restoreFocus: Bool) { dismissed = true }
    }
}
@main struct PaletteHookTest {
    @MainActor static func main() {
        let panel = PalettePanel()
        let core = AppCore.shared
        QuickLookCoordinator.shared.start()
        func key(_ code: Int) -> Bool {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, characters: " ",
                charactersIgnoringModifiers: " ", isARepeat: false, keyCode: UInt16(code))!
            return panel.notchcastPreviewOnSpace(event)
        }
        precondition(!key(kVK_Space))
        precondition(!key(kVK_DownArrow))
        core.palette.menuOpen = true
        precondition(!key(kVK_Space))
        core.palette.menuOpen = false
        core.palette.isEditingField = true
        precondition(!key(kVK_Space))
        core.palette.isEditingField = false
        core.palette.isControlListOpen = true
        precondition(!key(kVK_Space))
        core.palette.isControlListOpen = false
        core.palette.mode = .launcher
        precondition(!key(kVK_Space))
        core.palette.mode = .fileSearch
        panel.paletteState = PaletteState()
        precondition(!key(kVK_Space))
        panel.paletteState = core.palette
        NotchcastPreferences.enabled = false
        precondition(!key(kVK_DownArrow))
        precondition(!key(kVK_Space))
        precondition(!core.paletteCoordinator.dismissed)
        NotchcastPreferences.enabled = true
        precondition(!key(kVK_DownArrow))
        precondition(key(kVK_Space))
        precondition(core.paletteCoordinator.dismissed)
        precondition(QuickLookCoordinator.shared.systemPreview.shown?.fileURL == core.fileSearch.results[0].url)
        print("PASS: production palette hook gates and arrow-to-Space presentation")
    }
}
