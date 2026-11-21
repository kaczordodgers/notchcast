// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/DictationIslandSession.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/DictationIslandNotice.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandNoticeQueue.swift
// notchcast-reads: Tinycast/Features/Dictation/Service/DictationCoordinator.swift
// notchcast-reads: Tinycast/Features/DictationExtras/Service/DictationExtrasCoordinator.swift
// notchcast-reads: Tinycast/Features/Notchcast/DictationIslandCoordinator.swift

import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-Notchcast-dictation-island-test: \(message)") }
}

/// #960: the island's dictation states, first sound to result, against an injected clock.
@main
struct DictationIslandTest {
    typealias Session = DictationIslandSession

    static func recording(copies: Bool = false) -> Session {
        var session = Session()
        session.begin(copies: copies, at: 100)
        return session
    }

    static func ended(copies: Bool = false, _ change: (inout Session) -> Void = { _ in },
                      covered: Bool = false) -> Session.Outcome? {
        var session = recording(copies: copies)
        _ = session.transcribe()
        change(&session)
        session.end(completed: true)
        return session.settle(generation: session.generation, covered: covered)
    }

    static func checkPlacement() {
        var session = Session()
        check(!session.place(on: 2), "placement: idle ignores a display")
        session.begin(copies: false, at: 0)
        check(session.display == nil && session.place(on: 2), "placement: recording starts on the resting pill")
        check(!session.place(on: 2) && session.display == 2, "placement: an unchanged display does not repost")
        check(session.place(on: 3), "placement: recording follows a different display")
        _ = session.transcribe()
        check(session.place(on: nil) && session.display == nil, "placement: nil returns to the resting pill")
        _ = session.cleanUp()
        check(session.place(on: 2), "placement: cleanup takes a new display")
        session.end(completed: true)
        check(!session.place(on: 3) && session.display == 2, "placement: ending fixes the display")
        _ = session.settle(generation: session.generation, covered: false)
        check(!session.place(on: nil) && session.display == 2, "placement: a picked result does not move")
        session.begin(copies: false, at: 1)
        check(session.display == nil && !session.place(on: nil), "placement: begin clears the previous display")

        let coordinator = (try? String(contentsOfFile: "Tinycast/Features/Notchcast/DictationIslandCoordinator.swift",
                                       encoding: .utf8)) ?? ""
        let stand = coordinator.components(separatedBy: "private func stand(in:").last ?? ""
        guard let capture = stand.range(of: "captureDisplay()"), let hold = stand.range(of: "presenter?.holdKeys(")
        else { fatalError("placement: stand must capture the display source and hold keys") }
        check(capture.lowerBound < hold.lowerBound, "placement: stand captures the display source before holding keys")
    }

    static func main() {
        checkPlacement()
        var session = recording()
        check(session.phase == .recording && session.elapsed == "0:00", "1: begin records from 0:00")
        check(session.meter == [0, 0, 0, 0] && session.holdsKeys, "1: four bars at the floor, keys held")
        var notice = IslandNotice(dictation: session)!
        check(notice.isHeadline && notice.line == "0:00  Return to Paste · Esc to Cancel", "1: the hint headlines")

        let loud = [Float](repeating: 1, count: 21)
        check(session.hear(levels: loud, at: 100.2), "2: a bar's step change reposts")
        check(session.meter == [1, 1, 1, 1], "2: a full band fills its bar")
        check(!session.hear(levels: loud, at: 100.5), "2: no step or second changed, no repost")
        check(!session.hear(levels: loud.map { $0 * 0.95 }, at: 100.6), "2: a move inside a step reposts nothing")
        check(session.hear(levels: loud, at: 101.0), "2: silence reposts once a second")
        var bands = [Float](repeating: 0, count: 21)
        bands[2] = 1
        _ = session.hear(levels: bands, at: 101.1)
        check(session.bars == [7, 0, 0, 0], "2: bar 0 reads band 2 of 21")
        bands = [Float](repeating: 0, count: 21)
        bands[18] = 0.5
        _ = session.hear(levels: bands, at: 101.2)
        check(session.bars == [0, 0, 0, 4], "2: bar 3 reads band 18, in eight steps")

        check(session.elapsed == "0:01", "3: the clock is m:ss")
        _ = session.hear(levels: bands, at: 100 + 599)
        check(session.elapsed == "9:59", "3: 9:59")
        _ = session.hear(levels: bands, at: 100 + 600)
        check(session.elapsed == "10:00", "3: then 10:00")
        check(IslandProgress.shape(of: "9:59") != IslandProgress.shape(of: "10:00")
              && IslandProgress.shape(of: "0:07") == IslandProgress.shape(of: "9:59"), "3: shape changes only at 10:00")

        var idle = Session()
        check(!idle.transcribe() && !idle.cleanUp(), "4: neither step runs without a session")
        check(!session.cleanUp(), "4: cleanup only from transcribing")
        check(session.transcribe() && session.phase == .transcribing, "4: transcribe from recording")
        check(!session.transcribe() && !session.hear(levels: loud, at: 900), "4: no way back; levels ignored")
        check(session.cleanUp() && !session.cleanUp() && !session.transcribe(), "4: cleanup, then no way back")

        var covered = session
        check(!covered.cleanupFailed(covered: true) && !covered.raw, "5: covered, the stock sentence shows")
        check(session.cleanupFailed(covered: false) && session.raw, "5: cleaning up, the island takes it")
        var early = recording()
        check(!early.cleanupFailed(covered: false), "5: not cleaning up, stock speaks")

        check(ended { $0.delivered(empty: false) } == .pasted, "6, 9: text reached gives pasted")
        check(ended { $0.delivered(empty: true) } == .noSpeech, "6, 9: no text gives no speech")
        check(ended() == .noSpeech, "9: nothing delivered gives no speech")

        for (text, outcome) in [(Session.noSpeech, Session.Outcome.noSpeech),
                                (Session.pasteFailed, .pasteFailed), (Session.partLost, .partLost)] {
            var live = recording()
            live.end(completed: true)
            check(live.message(text, covered: false), "7: \(text) is swallowed")
            check(live.settle(generation: live.generation, covered: false) == outcome, "7, 9: \(text) gives \(outcome)")
        }
        var odd = recording()
        odd.end(completed: true)
        check(!odd.message("The model crashed", covered: false), "7: any other text still shows")
        check(odd.settle(generation: odd.generation, covered: false) == .failed, "7: and reads as failed")
        check(!idle.message(Session.noSpeech, covered: false), "7: idle swallows nothing")
        var hidden = recording()
        check(!hidden.message(Session.noSpeech, covered: true), "7: covered swallows nothing")
        var lost = recording()
        _ = lost.transcribe()
        _ = lost.cleanUp()
        check(lost.cleanupFailed(covered: false), "7: cleanup fails first")
        lost.delivered(empty: false)
        lost.end(completed: true)
        check(lost.message(Session.pasteFailed, covered: false), "7: then the paste fails")
        check(lost.settle(generation: lost.generation, covered: false) == .pasteFailed, "7: couldn't paste wins")

        for step in 0...3 {
            var live = recording()
            if step > 0 { _ = live.transcribe() }
            if step > 1 { _ = live.cleanUp() }
            if step > 2 { live.end(completed: true) }
            live.end(completed: false)
            check(live.phase == .idle && !live.holdsKeys, "8: a cancel at step \(step) is idle at once")
            check(live.settle(generation: live.generation, covered: false) == nil, "8: and shows no result")
        }

        var ending = recording()
        ending.delivered(empty: false)
        ending.end(completed: true)
        check(ending.phase == .ending, "9: a completed end waits a hop")
        var twice = ending
        check(!twice.end(completed: true) && twice.phase == .ending, "9: a second end starts no second hop")
        check(twice.settle(generation: twice.generation, covered: false) == .pasted, "9: the result still shows")
        var once = recording()
        check(once.end(completed: true), "9: the first completed end starts the hop")
        var stale = ending
        stale.begin(copies: false, at: 0)
        check(stale.settle(generation: ending.generation, covered: false) == nil && stale.phase == .recording,
              "10: an older settle leaves a newer session alone")
        var hiddenEnd = ending
        check(hiddenEnd.settle(generation: ending.generation, covered: true) == nil && hiddenEnd.phase == .idle,
              "10: a covered result is dropped, not shown late")
        check(ended({ _ = $0.cleanUp(); _ = $0.cleanupFailed(covered: false); $0.delivered(empty: false) })
              == .pastedRaw, "9: the raw flag gives pasted without cleanup")
        check(ended(copies: true) { _ = $0.cleanUp(); _ = $0.cleanupFailed(covered: false); $0.delivered(empty: false) }
              == .copiedRaw, "9: copy-only with the raw flag gives copied without cleanup")
        var copying = recording(copies: true)
        check(IslandNotice(dictation: copying)!.text == "Return to Copy · Esc to Cancel", "1: copy-only hint")
        copying.delivered(empty: false)
        copying.end(completed: true)
        check(copying.settle(generation: copying.generation, covered: false) == .copied, "9: copy-only gives copied")

        var keys = recording()
        keys.delivered(empty: false)
        check(!keys.holdsKeys, "11: keys go back once the text is final")
        keys = recording()
        keys.end(completed: true)
        check(!keys.holdsKeys, "11: or once the session ends")
        _ = keys.settle(generation: keys.generation, covered: false)
        check(!keys.holdsKeys, "11: never after")

        notice = IslandNotice(dictation: recording())!
        check(notice.symbol == "mic" && notice.meter?.count == 4 && notice.progress?.fraction == nil, "12: recording")
        check(notice.spoken == "Recording dictation, Return to finish, Escape to cancel", "12: one spoken sentence")
        var later = recording()
        _ = later.hear(levels: loud, at: 107)
        check(IslandNotice(dictation: later)!.spoken == notice.spoken, "12: VoiceOver never hears the time tick")
        _ = later.transcribe()
        notice = IslandNotice(dictation: later)!
        check(notice.text == "Transcribing" && notice.symbol == "waveform" && !notice.isHeadline
              && notice.meter == nil, "12: transcribing")
        _ = later.cleanUp()
        notice = IslandNotice(dictation: later)!
        check(notice.text == "Cleaning Up" && notice.symbol == "sparkles" && !notice.isHeadline, "12: cleaning up")
        later.end(completed: true)
        check(IslandNotice(dictation: later) == nil && IslandNotice(dictation: Session()) == nil,
              "12: nothing live while ending or idle")
        let results: [(Session.Outcome, String, String, Bool, Bool)] = [
            (.pasted, "Pasted", "checkmark", false, true), (.copied, "Copied", "checkmark", false, true),
            (.noSpeech, "No Speech Detected", "mic.slash", false, false),
            (.pastedRaw, "Pasted Without Cleanup", "exclamationmark.triangle", true, false),
            (.copiedRaw, "Copied Without Cleanup", "exclamationmark.triangle", true, false),
            (.pasteFailed, "Couldn't Paste", "exclamationmark.triangle", true, false),
            (.partLost, "Some Text Wasn't Pasted", "exclamationmark.triangle", true, false),
            (.failed, "Dictation Failed", "exclamationmark.triangle", true, false),
        ]
        for (outcome, text, symbol, failure, quiet) in results {
            let notice = IslandNotice(dictation: outcome)
            check(notice.text == text && notice.symbol == symbol && notice.isFailure == failure
                  && notice.quiet == quiet && notice.progress == nil && notice.id == "dictation", "12: \(text)")
            check(notice.dwell == (failure ? 4 : 2.4), "12: \(text) dwells \(notice.dwell) s")
        }

        let stock = (try? String(contentsOfFile: "Tinycast/Features/Dictation/Service/DictationCoordinator.swift",
                                 encoding: .utf8)) ?? ""
        for sentence in [Session.noSpeech, Session.pasteFailed, Session.partLost] {
            check(stock.contains("String(localized: \"\(sentence)\")"), "13: stock still says \"\(sentence)\"")
        }
        var queue = IslandNoticeQueue()
        let pasted = IslandNotice(dictation: .pasted)
        let recordingSpoken = IslandNotice(dictation: recording())!.spoken
        for start in [0.0, 1.0] {
            queue.end(IslandNotice.dictationID, at: start)
            queue.post(IslandNotice(dictation: recording())!, at: start)
            check(queue.announcement() == recordingSpoken, "14: recording at \(start) s is heard")
            queue.post(pasted, at: start + 0.5)
            check(queue.remaining(at: start + 0.5) == pasted.dwell, "14: the result dwells")
            check(queue.announcement() == "Pasted", "14: a matching result inside the last one's dwell is heard")
        }
        queue.post(IslandNotice(dictation: recording())!, at: 2)
        _ = queue.announcement()
        queue.post(pasted, at: 2.5)
        check(queue.announcement() == nil, "14: without the end, the recording inherits the result and it is lost")
        missingCleanupModel()
        print("PASS: dictation island session (15 rules)")
    }

    static func missingCleanupModel() {
        let sentence = "Cleanup has no model, so the raw text was pasted"
        for copies in [false, true] {
            var session = recording(copies: copies)
            _ = session.transcribe()
            _ = session.cleanUp()

            var unavailable = session
            let hud = unavailable.message(sentence, covered: true) ? nil : sentence
            unavailable.delivered(empty: false)
            unavailable.end(completed: true)
            check(hud == sentence && unavailable.settle(generation: unavailable.generation, covered: true) == nil,
                  "15: a covered island leaves the original message to the HUD")
            check(!unavailable.message(sentence, covered: false), "15: an idle island also leaves the message to the HUD")

            check(session.message(sentence, covered: false), "15: the active island consumes the missing-model report")
            session.delivered(empty: false)
            session.end(completed: true)
            var coveredAtDelivery = session
            let fallback = coveredAtDelivery.settle(generation: coveredAtDelivery.generation, covered: true)
            guard let result = session.settle(generation: session.generation, covered: false) else {
                fatalError("15: missing-model notice is absent")
            }
            check(fallback == result, "15: coverage during delivery preserves the missing-model result for the HUD")
            let notice = IslandNotice(dictation: result)
            if !copies { check(notice.spoken == sentence, "15: VoiceOver reads the original HUD sentence") }
            check(notice.text == (copies ? "No Cleanup Model · Copied Raw" : "No Cleanup Model · Pasted Raw")
                  && notice.isFailure, "15: the notice names the missing model and the raw delivery")

            session.begin(copies: copies, at: 200)
            session.delivered(empty: false)
            session.end(completed: true)
            check(session.settle(generation: session.generation, covered: false) == (copies ? .copied : .pasted),
                  "15: the next result has no missing-model reason")
        }

        let extras = (try? String(
            contentsOfFile: "Tinycast/Features/DictationExtras/Service/DictationExtrasCoordinator.swift",
            encoding: .utf8)) ?? ""
        guard let missing = extras.range(of: "case .failed(.noModel):"),
              let other = extras.range(of: "case .failed where cleanupFailed():"),
              missing.upperBound < other.lowerBound else {
            fatalError("15: missing model must be routed before generic cleanup failures")
        }
        let route = extras[missing.upperBound..<other.lowerBound]
        check(route.contains("core.dictationCoordinator.showMessage(") && route.contains(sentence),
              "15: the missing-model message is offered to the island before the HUD")
    }
}
