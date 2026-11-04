// notchcast-sources: Tinycast/Features/Dictation/Model/*.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationCoordinator.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationInsertionContext.swift
// notchcast-sources: Tinycast/Features/AI/UI/ChatComposerTextView.swift
// notchcast-sources: Tinycast/Features/TextInjection/Service/*.swift Tinycast/Features/Snippets/Model/*.swift
// notchcast-sources: Tinycast/Platform/AccessibilityText.swift Tinycast/Platform/PasteboardFiles.swift
// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
import AppKit
import SwiftUI

@main @MainActor
struct EnglishTriggerTest {
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try await testEnglishTrigger()
        print("PASS English trigger delivery")
    }
    private static func testEnglishTrigger() async throws {
        let fixture = Fixture()
        Paster.copies = []
        DictationCoordinator.englishTranscriptStage = { _, _ in "Send the report." }
        defer {
            DictationCoordinator.englishTranscriptStage = nil
            Paster.copies = []
        }
        fixture.coordinator.triggerStarted(inEnglish: true)
        try await wait { fixture.capture.isRecording }
        fixture.coordinator.triggerFinished()
        try await wait { fixture.models.pending != nil }
        fixture.models.finish("Wyślij raport.")
        try await wait { !Paster.copies.isEmpty }
        expect(Paster.copies == ["Send the report."], "The trigger copies one English transcript")
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }

    @MainActor
    private final class Fixture {
        let settings = AppSettings()
        let models = DictationModelStore()
        let queue = DeliveryQueue()
        var messages: [String] = []
        lazy var coordinator = DictationCoordinator(
            settings: settings, hotKeys: HotKeyManager(), models: models,
            injector: TextInjector(
                clipboardManager: ClipboardManager(), settings: settings, deliveryQueue: queue),
            audioDucker: DictationAudioDucker(), confirmEnable: { false },
            showMessage: { [weak self] message, _ in self?.messages.append(message) })

        var capture: DictationCapture { DictationCapture.latest! }
        var panel: DictationPanelController { DictationPanelController.latest! }

    }
}

@MainActor
final class AppSettings {
    var snippetsEnabled = false
    var dictationEnabled = true
    var dictationMode = DictationMode.toggle
    var dictationModel = DictationModel.redux
    var dictationMicrophone: String?
    var dictationLanguage: String?
    var dictationDestination = DictationDestination.copy
    var dictationAdaptsCapitalization = true
    var dictationLiveInsertion = false
    var dictationPlaysSounds = true
}

enum HotKeyAction { case dictation }

@MainActor
final class HotKeyManager {
    struct Binding {
        var shortcut: Int?
        var holdKey: Int?
    }
    func binding(for action: HotKeyAction) -> Binding? { nil }
    func conflictOwner(of binding: Binding, excluding action: HotKeyAction) -> String? { nil }
}

@MainActor
final class DictationCapture {
    static weak var latest: DictationCapture?
    var onLevels: (([Float]) -> Void)?
    var onLimit: (() -> Void)?
    var isRecording = false
    var isBluetooth = false
    var stopCount = 0

    init() { Self.latest = self }
    func start(microphoneID: String?) async throws { isRecording = true }
    var snapshotSamples: [Float] = []
    func snapshot() -> [Float] { snapshotSamples }
    func stop() async -> [Float] {
        isRecording = false
        stopCount += 1
        return [Float](repeating: 0, count: 1_600)
    }
}

@MainActor
final class DictationModelStore {
    var pending: CheckedContinuation<String, any Error>?
    var finished = false

    func isInstalled(_ model: DictationModel) -> Bool { true }
    func download(_ model: DictationModel) async throws {}
    func delete(_ model: DictationModel) async throws {}
    func stop() async {}
    func prepareForTermination() {}

    func transcribe(_ samples: [Float], model: DictationModel, language: String?) async throws -> String {
        defer { finished = true }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func finish(_ text: String) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: text)
    }
}

@MainActor
final class DictationPanelController {
    enum Phase { case listening, transcribing }
    @MainActor
    final class State {
        var phase = Phase.listening
        var levels: [Float] = []
    }
    static weak var latest: DictationPanelController?
    let state = State()
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?
    var isVisible = false
    init() { Self.latest = self }
    func show() { isVisible = true }
    func close() { isVisible = false }
}

@MainActor
enum AudioEvents {
    static var log: [String] = []
}

@MainActor
final class DictationAudioDucker {
    func begin() { AudioEvents.log.append("duck") }
    func end() { AudioEvents.log.append("fade up") }
    func restoreImmediately() { AudioEvents.log.append("restore") }
}

@MainActor
final class DictationCueRunner {
    enum Cue { case start, stop }

    func play(_ cue: Cue) { AudioEvents.log.append(cue == .start ? "start cue" : "stop cue") }
}

@MainActor
final class ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")
    func prepareForTinycastPasteboardMutation() {}
    func synchronizeAfterTinycastPasteboardMutation(changeCount: Int) {}
    func pauseCapture() {}
    func resumeCapture() {}
}

enum Permissions {
    @discardableResult
    static func ensureAccessibility() -> Bool { false }
    static func isAccessibilityTrusted() -> Bool { false }
}

@MainActor
enum Paster {
    static let tinycastEventTag: Int64 = 0x54494E59
    static var copies: [String] = []
    static func copyPlainText(_ text: String) { copies.append(text) }
    static func postCommandV(toPid pid: pid_t? = nil) {}
    static func postCommandC(toPid pid: pid_t? = nil) {}
}

enum DialogTone { case danger }
