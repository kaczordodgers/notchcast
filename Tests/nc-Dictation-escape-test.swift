// notchcast-sources: Tinycast/Features/Dictation/Model/*.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationCoordinator.swift
import AppKit
import Observation

@main
@MainActor
struct DictationEscapeTest {
    static func main() async throws {
        for transcribing in [false, true] {
            let fixture = Fixture()
            fixture.coordinator.pressed()
            try await wait { fixture.panel.isVisible }
            if transcribing {
                fixture.panel.onAccept?()
                try await wait { fixture.models.pending != nil }
            }
            fixture.panel.onCancel?()
            precondition(!fixture.panel.isVisible)
            if transcribing { fixture.models.finish() }
            try await wait { !fixture.capture.isRecording }
            for _ in 0..<20 { await Task.yield() }
            precondition(fixture.injector.calls == 0 && Paster.copies.isEmpty)
            precondition(fixture.models.calls == (transcribing ? 1 : 0))
            let phase = transcribing ? "transcription" : "recording"
            print("PASS Escape during \(phase): closed, stopped, no injection or clipboard write")
        }
        let fixture = Fixture()
        fixture.coordinator.pressed()
        try await wait { fixture.panel.isVisible }
        fixture.panel.onAccept?()
        try await wait { fixture.models.pending != nil }
        fixture.models.finish()
        try await wait { fixture.injector.calls == 1 }
        precondition(Paster.copies == ["Spoken words"])
        print("PASS Return/normal finish: one injection and requested clipboard copy")
    }

    static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out")
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor
    final class Fixture {
        let models = DictationModelStore()
        let injector = TextInjector()
        lazy var coordinator = DictationCoordinator(
            settings: AppSettings(), hotKeys: HotKeyManager(), models: models,
            injector: injector, audioDucker: DictationAudioDucker(),
            confirmEnable: { false }, showMessage: { _, _ in preconditionFailure("Unexpected error") })
        var panel: DictationPanelController { DictationPanelController.latest! }
        var capture: DictationCapture { DictationCapture.latest! }
    }
}

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

@MainActor final class DictationCapture {
    static weak var latest: DictationCapture?
    var onLevels: (([Float]) -> Void)?
    var onLimit: (() -> Void)?
    var isRecording = false
    var isBluetooth = false
    init() { Self.latest = self }
    func start(microphoneID: String?) async throws { isRecording = true }
    func stop() async -> [Float] { isRecording = false; return Array(repeating: 0, count: 1_600) }
    func snapshot() -> [Float] { [] }
}

@MainActor final class DictationModelStore {
    var pending: CheckedContinuation<String, any Error>?
    var calls = 0
    func isInstalled(_ model: DictationModel) -> Bool { true }
    func download(_ model: DictationModel) async throws {}
    func delete(_ model: DictationModel) async throws {}
    func stop() async {}
    func prepareForTermination() {}
    func transcribe(_ samples: [Float], model: DictationModel, language: String?) async throws -> String {
        calls += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish() { let continuation = pending; pending = nil; continuation?.resume(returning: "Spoken words") }
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
struct InjectedText { init(_ text: String) {} }
@MainActor final class TextInjector {
    var calls = 0
    func drain() async {}
    func deliver(
        _ text: InjectedText, target: InjectionTarget?, expectedKeyword: String?,
        keywordLength: Int, automaticGeneration: Int?, isValid: () -> Bool,
        onDelivered: () -> Void, onFailed: () -> Void
    ) {
        calls += 1
        precondition(isValid())
        onDelivered()
    }
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
@MainActor enum Paster {
    static var copies: [String] = []
    static func copyPlainText(_ text: String) { copies.append(text) }
}
enum Permissions { static func ensureAccessibility() {} }
enum DialogTone { case danger }
