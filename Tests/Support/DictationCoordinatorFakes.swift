import Foundation

@MainActor final class AppSettings {
    var dictationEnabled = true
    var dictationMode = DictationMode.toggle
    var dictationModel = DictationModel.redux
    var dictationMicrophone: String?
    var dictationLanguage: String?
    var dictationDestination = DictationDestination.both
    var dictationAdaptsCapitalization = true
    var dictationLiveInsertion = false
    var dictationPlaysSounds = false
}

enum HotKeyAction { case dictation }
@MainActor final class HotKeyManager {
    struct Binding { var shortcut: Int?; var holdKey: Int? }
    func binding(for action: HotKeyAction) -> Binding? { nil }
    func conflictOwner(of binding: Binding, excluding action: HotKeyAction) -> String? { nil }
}

@MainActor final class DictationPanelController {
    enum Phase { case listening, transcribing }
    @MainActor final class State { var phase = Phase.listening; var levels: [Float] = [] }
    static weak var latest: DictationPanelController?
    let state = State()
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?
    var isVisible = false
    init() { Self.latest = self }
    func show() { isVisible = true }
    func close() { isVisible = false }
}

@MainActor protocol InjectableTextView: AnyObject {}
@MainActor struct InjectionTarget {
    var ownEditor: (any InjectableTextView)?
    static func current() -> Self? { nil }
    static func ownEditor(_ editor: any InjectableTextView) -> Self { Self(ownEditor: editor) }
}
@MainActor enum DictationInsertionContext {
    static func read(in target: InjectionTarget?) -> DictationTextFormatter.Context? { nil }
}
@MainActor final class DictationAudioDucker {
    func begin() {}
    func end() {}
    func restoreImmediately() {}
}
@MainActor final class DictationCueRunner {
    enum Cue { case start, stop }
    func play(_ cue: Cue) {}
}
enum Permissions { static func ensureAccessibility() {} }
