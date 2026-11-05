// notchcast-sources: Tinycast/Features/Dictation/Model/*.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationCoordinator.swift
// notchcast-sources: Tinycast/Features/DictationCleanup/Service/DictationCleanup+Installation.swift
import AppKit
import Observation

@main
@MainActor
struct DictationHistoryLiveTest {
    static func main() async throws {
        for (tail, answer) in [(800, "raw tail"), (3_200, "raw tail"), (3_200, "fail")] {
            let recorded = tail < 1_600 || answer == "fail" ? "" : " raw tail"
            Fixture.expectsError = answer == "fail"
            let fixture = Fixture()
            fixture.settings.dictationLiveInsertion = true
            var records: [(String, String)] = []
            DictationCleanup.transcriptObserver = { records.append(($0, $1)) }
            DictationCleanup.setHistoryEnabled(true)
            DictationCleanup.install()
            fixture.coordinator.pressed()
            try await wait { fixture.panel.isVisible }
            for words in ["First chunk", "Second chunk", "Third chunk"] {
                fixture.models.answer = words
                fixture.capture.samples += Array(repeating: 0.5, count: 128_000)
                let count = fixture.injector.calls
                try await wait(seconds: 4) { fixture.injector.calls > count }
            }
            let live = fixture.injector.text
            fixture.capture.samples.removeLast(1_600)
            fixture.capture.samples += Array(repeating: 0.5, count: tail)
            fixture.models.answer = answer
            fixture.panel.onAccept?()
            try await wait { !fixture.panel.isVisible }
            precondition(records.count == 1, "One entry per live dictation")
            precondition(records[0].0 == live + recorded)
            precondition(records[0].1 == fixture.injector.text)
            precondition(DictationCleanup.inputs == (recorded.isEmpty ? [] : ["raw tail"]))
            print("PASS live tail \(tail) \(answer): one full history entry equals inserted text; cleanup tail only")
            DictationCleanup.inputs = []
        }
        Fixture.expectsError = false
        let fixture = Fixture()
        var records: [(String, String)] = []
        DictationCleanup.transcriptObserver = { records.append(($0, $1)) }
        fixture.coordinator.pressed()
        try await wait { fixture.panel.isVisible }
        fixture.models.answer = "raw tail"
        fixture.panel.onAccept?()
        try await wait { !fixture.panel.isVisible }
        precondition(records.count == 1 && records[0].0 == "raw tail" && records[0].1 == "cleaned tail")
        print("PASS Live Insertion off: raw and cleaned history unchanged")
    }


    static func wait(seconds: Int = 3, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out")
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor
    final class Fixture {
        let models = DictationModelStore()
        let injector = TextInjector()
        let settings = AppSettings()
        lazy var coordinator = DictationCoordinator(
            settings: settings, hotKeys: HotKeyManager(), models: models,
            injector: injector, audioDucker: DictationAudioDucker(),
            confirmEnable: { false }, showMessage: { _, _ in precondition(Fixture.expectsError, "Unexpected error") })
        static var expectsError = false
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
    var samples = Array(repeating: Float(0.5), count: 1_600)
    init() { Self.latest = self }
    func start(microphoneID: String?) async throws { isRecording = true }
    func stop() async -> [Float] { isRecording = false; return samples }
    func snapshot() -> [Float] { samples }
}

@MainActor final class DictationModelStore {
    var pending: CheckedContinuation<String, any Error>?
    var calls = 0
    var answer = "Spoken words"
    func isInstalled(_ model: DictationModel) -> Bool { true }
    func download(_ model: DictationModel) async throws {}
    func delete(_ model: DictationModel) async throws {}
    func stop() async {}
    func prepareForTermination() {}
    func transcribe(_ samples: [Float], model: DictationModel, language: String?) async throws -> String {
        calls += 1
        if answer == "fail" { throw CocoaError(.featureUnsupported) }
        return answer
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
struct InjectedText { let text: String; init(_ text: String) { self.text = text } }
@MainActor final class TextInjector {
    var calls = 0
    var text = ""
    func drain() async {}
    func deliver(
        _ text: InjectedText, target: InjectionTarget?, expectedKeyword: String?,
        keywordLength: Int, automaticGeneration: Int?, isValid: () -> Bool,
        onDelivered: () -> Void, onFailed: () -> Void
    ) {
        calls += 1
        self.text += text.text
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

@MainActor enum DictationCleanup {
    static var inputs: [String] = []
    static func process(_ raw: String, language: String?) async -> String {
        inputs.append(raw)
        return "cleaned tail"
    }
}
