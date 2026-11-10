// notchcast-sources: Tinycast/Features/Notchcast/Dictation/DictationFamily.swift Tests/dictation-family-stubs.swift
import Foundation
import Synchronization

private final class Calls: Sendable {
    private let log = Mutex<[String]>([])
    var all: [String] { log.withLock { $0 } }
    func add(_ call: String) { log.withLock { $0.append(call) } }
}

@main
@MainActor
struct DictationFamilyOwnerTest {
    static func main() async {
        let calls = Calls()
        let family = DictationFamily(process: { raw, _, english, onFallback in
            calls.add((english ? "english:" : "cleanup:") + raw)
            if raw == "fails" { await onFallback() }
            return raw.uppercased()
        })
        session(family)
        await stages(family, calls)
        await english(family, calls)
        print("PASS dictation family owner: session reads, stage installation, history gate, English routing")
    }

    private static func session(_ family: DictationFamily) {
        precondition(!family.isAvailable && !family.isRecording)
        family.start(inEnglish: true)
        var coordinator: DictationCoordinator? = DictationCoordinator()
        family.bind(coordinator!)
        precondition(family.isAvailable && !family.isRecording)
        family.toggleEnglish()
        precondition(family.isRecording && coordinator!.starts == 1)
        family.toggleEnglish()
        precondition(!family.isRecording && coordinator!.finishes == 1)
        family.cancel()
        family.cancelEnglish()
        precondition(coordinator!.cancels == 1 && coordinator!.englishCancels == 1)
        coordinator!.isEnabled = false
        precondition(!family.isAvailable)
        coordinator = nil
        precondition(!family.isRecording && !family.isAvailable)
    }

    private static func stages(_ family: DictationFamily, _ calls: Calls) async {
        DictationCoordinator.transcriptStage = nil
        DictationCoordinator.transcriptObserver = nil
        var seen: [String] = []
        family.historySink = { seen.append($0 + "→" + $1) }
        precondition(DictationCoordinator.transcriptStage == nil && DictationCoordinator.transcriptObserver == nil)

        family.setCleanup(true)
        precondition(DictationCoordinator.transcriptObserver == nil)
        let cleaned = await DictationCoordinator.transcriptStage!("raw", "pl")
        precondition(cleaned == "RAW" && calls.all == ["cleanup:raw"])
        family.observeTranscript(raw: "raw", cleaned: cleaned)
        precondition(seen.isEmpty, "History off: nothing recorded")

        family.setHistory(true)
        DictationCoordinator.transcriptObserver!("raw", "RAW")
        precondition(seen == ["raw→RAW"])
        DictationCoordinator.transcriptObserver!(" \n", "")
        precondition(seen.count == 1, "Blank transcripts are not recorded")

        family.setCleanup(false)
        let untouched = await DictationCoordinator.transcriptStage!("only history", nil)
        precondition(untouched == "only history" && calls.all == ["cleanup:raw"], "History alone leaves text raw")

        family.setHistory(false)
        precondition(DictationCoordinator.transcriptStage == nil && DictationCoordinator.transcriptObserver == nil)

        family.setHistory(true)
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            family.observeTranscript(raw: "late", cleaned: "late")
        }
        await cancelled.value
        precondition(seen.count == 1, "A cancelled take is not recorded")
    }

    private static func english(_ family: DictationFamily, _ calls: Calls) async {
        var failures = 0
        family.installEnglish { failures += 1 }
        var seen: [String] = []
        family.historySink = { seen.append($0 + "→" + $1) }
        family.setHistory(true)
        let translated = await DictationCoordinator.englishTranscriptStage!("wyślij", "pl")
        precondition(translated == "WYŚLIJ" && failures == 0 && seen == ["wyślij→WYŚLIJ"])
        precondition(calls.all.last == "english:wyślij")
        let failed = await DictationCoordinator.englishTranscriptStage!("fails", nil)
        precondition(failed == "FAILS" && failures == 1)
        family.setHistory(false)
        _ = await DictationCoordinator.englishTranscriptStage!("quiet", nil)
        precondition(seen.count == 2, "English history follows the history switch")
    }
}
