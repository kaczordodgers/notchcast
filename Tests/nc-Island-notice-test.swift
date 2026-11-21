// notchcast-linux-ok
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandNoticeQueue.swift
import Foundation

@main
struct IslandNoticeTest {
    static func main() {
        var queue = IslandNoticeQueue()
        queue.post(IslandNotice(id: "saved", text: "Saved"), at: 0)
        precondition(near(queue.remaining(at: 1), 1.4), "A notice dwells 2.4 s by default")
        queue.expire(at: 2)
        precondition(queue.notice?.id == "saved", "Nothing expires before its dwell runs out")
        queue.expire(at: 2.4)
        precondition(queue.notice == nil, "The notice leaves once its dwell runs out")

        queue.post(IslandNotice(id: "failed", text: "Failed", isFailure: true), at: 0)
        precondition(near(queue.remaining(at: 1), 3), "A failure notice dwells 4 s by default")
        queue.post(IslandNotice(id: "failed", text: "Failed", isFailure: true, seconds: 5), at: 0)
        precondition(near(queue.remaining(at: 1), 4), "A failure keeps a dwell its poster sets")
        queue.end("failed", at: 1)

        queue.post(IslandNotice(id: "sync", text: "Syncing", progress: IslandProgress(fraction: 0.2, headline: false)),
                   at: 10)
        precondition(queue.remaining(at: 100) == nil && queue.notice?.isHeadline == false,
                     "An untitled progress stays compact until it is ended")
        queue.end("sync", at: 100)
        precondition(queue.notice == nil, "Ending a progress notice clears it")

        queue.post(IslandNotice(id: "page", text: "Page", progress: IslandProgress(fraction: 0.1)), at: 0)
        precondition(queue.notice?.isHeadline == true && near(queue.remaining(at: 1), 1.4),
                     "A titled progress headlines for one message dwell")
        queue.post(IslandNotice(id: "page", text: "Page", progress: IslandProgress(fraction: 0.4)), at: 1)
        precondition(near(queue.remaining(at: 1), 1.4), "A progress repost keeps the headline time its title has left")
        queue.expire(at: 2.4)
        precondition(queue.notice?.id == "page" && queue.notice?.isHeadline == false && queue.remaining(at: 99) == nil,
                     "A spent headline leaves the progress compact until it is ended")
        queue.post(IslandNotice(id: "page", text: "Page", progress: IslandProgress(fraction: 0.8)), at: 3)
        precondition(queue.notice?.isHeadline == false && queue.notice?.progress?.fraction == 0.8,
                     "A same-title repost stays compact and moves its ring")
        queue.post(IslandNotice(id: "page", text: "2 of 2: Next", progress: IslandProgress(fraction: 0)), at: 4)
        precondition(queue.notice?.isHeadline == false && queue.remaining(at: 99) == nil,
                     "A compact progress stays compact whatever its text, until it is ended")
        queue.end("page", at: 4.5)
        queue.post(IslandNotice(id: "page", text: "2 of 2: Next", progress: IslandProgress(fraction: 0)), at: 5)
        precondition(queue.notice?.isHeadline == true && near(queue.remaining(at: 5), 2.4),
                     "An ended progress posted again headlines again")
        queue.post(IslandNotice(id: "done", text: "Saved"), at: 6)
        precondition(queue.notice?.isHeadline == true, "A result notice headlines")
        queue.expire(at: 8.4)
        precondition(queue.notice?.id == "page" && near(queue.remaining(at: 8.4), 1.4),
                     "A covered headline resumes with the time it had left")
        queue.post(IslandNotice(id: "page", text: "3 of 3: Last", progress: IslandProgress(fraction: 0)), at: 9)
        precondition(queue.notice?.isHeadline == true && near(queue.remaining(at: 9), 0.8),
                     "A new text while headlining keeps the time left, so a fast playlist settles")
        queue.end("page", at: 10)

        queue.post(IslandNotice(id: "a", text: "First"), at: 0)
        queue.post(IslandNotice(id: "b", text: "Second", seconds: 4), at: 1)
        precondition(queue.notice?.id == "b" && near(queue.remaining(at: 2), 3), "A newer notice covers with its own dwell")
        queue.expire(at: 5)
        precondition(queue.notice?.id == "a" && near(queue.remaining(at: 5), 1.4),
                     "The covered notice returns with the dwell it had left")

        queue.pause(true, at: 5.4)
        precondition(queue.remaining(at: 50) == nil, "A level freezes the notice's dwell")
        queue.expire(at: 50)
        precondition(queue.notice?.id == "a", "A paused notice never expires")
        queue.pause(false, at: 60)
        precondition(near(queue.remaining(at: 60), 1), "Resuming runs only the dwell left before the level")
        queue.post(IslandNotice(id: "c", text: "Third"), at: 60)
        precondition(near(queue.remaining(at: 60), 2.4), "A notice posted under no level starts its dwell at once")
        queue.pause(true, at: 61)
        queue.post(IslandNotice(id: "d", text: "Fourth"), at: 62)
        precondition(queue.remaining(at: 70) == nil, "A notice posted under a level waits for it")

        var reposts = IslandNoticeQueue()
        reposts.post(IslandNotice(id: "a", text: "First"), at: 0)
        reposts.post(IslandNotice(id: "b", text: "Second"), at: 0)
        reposts.post(IslandNotice(id: "a", text: "First again"), at: 1)
        precondition(reposts.notice?.id == "b", "A repost keeps its place under a newer notice")
        reposts.end("b", at: 1)
        precondition(reposts.notice?.text == "First again" && near(reposts.remaining(at: 1), 2.4),
                     "A repost restarts its dwell and carries its new text")
        reposts.post(IslandNotice(id: "z", text: "Other"), at: 1)
        reposts.end("a", at: 1)
        precondition(reposts.notice?.id == "z", "Ending a covered notice leaves the top alone")

        var spoken = IslandNoticeQueue()
        spoken.post(IslandNotice(id: "a", text: "First"), at: 0)
        precondition(spoken.announcement() == "First" && spoken.announcement() == nil,
                     "A notice is announced once when it first shows")
        spoken.post(IslandNotice(id: "b", text: "Second"), at: 0)
        precondition(spoken.announcement() == "Second", "A covering notice is announced")
        spoken.end("b", at: 0)
        precondition(spoken.announcement() == nil, "A returning notice is not announced again")
        spoken.post(IslandNotice(id: "a", text: "First", progress: IslandProgress(fraction: 0.5)), at: 0)
        precondition(spoken.announcement() == nil, "A same-text repost stays silent")
        spoken.post(IslandNotice(id: "a", text: "Verifying"), at: 0)
        precondition(spoken.announcement() == "Verifying", "A repost with new text is announced")
        spoken.post(IslandNotice(id: "a", text: "First"), at: 0)
        precondition(spoken.announcement() == nil, "A text an id already said stays silent when it comes back")

        var hidden = IslandNoticeQueue()
        hidden.post(IslandNotice(id: "a", text: "First"), at: 0)
        hidden.post(IslandNotice(id: "b", text: "Second", progress: IslandProgress(fraction: 0.1)), at: 0)
        _ = hidden.announcement()
        hidden.post(IslandNotice(id: "a", text: "Changed"), at: 0)
        hidden.end("b", at: 0)
        precondition(hidden.announcement() == "Changed", "A covered notice whose text changed is heard on return")

        var ticking = IslandNoticeQueue()
        ticking.post(IslandNotice(id: "t", text: "a.iso · 1%", progress: IslandProgress(fraction: 0.01)), at: 0)
        precondition(ticking.announcement() == "a.iso · 1%", "A progress is announced when it first shows")
        ticking.post(IslandNotice(id: "t", text: "a.iso · 2%", progress: IslandProgress(fraction: 0.02)), at: 1)
        precondition(ticking.announcement() == nil, "A progress whose numbers tick stays silent")
        ticking.post(IslandNotice(id: "t", text: "a.iso failed", isFailure: true), at: 2)
        precondition(ticking.announcement() == "a.iso failed", "A progress turning into its outcome is announced")
        ticking.end("t", at: 3)
        ticking.post(IslandNotice(id: "t", text: "b.iso · 5%", progress: IslandProgress(fraction: 0.05)), at: 3)
        precondition(ticking.announcement() == "b.iso · 5%", "A progress posted again after its end is announced")

        var quick = IslandNoticeQueue()
        quick.post(IslandNotice(id: "ip", text: "Copied 10.0.0.2"), at: 0)
        precondition(quick.announcement() == "Copied 10.0.0.2", "A copied address is announced")
        quick.post(IslandNotice(id: "ip", text: "Looking Up Public IP…", progress: IslandProgress(fraction: nil)), at: 1)
        precondition(quick.announcement() == "Looking Up Public IP…", "A progress after a result of its id is announced")
        quick.post(IslandNotice(id: "ip", text: "Copied 1.2.3.4"), at: 2)
        precondition(quick.announcement() == "Copied 1.2.3.4", "Its result is announced")
        quick.post(IslandNotice(id: "ip", text: "Looking Up Public IP…", progress: IslandProgress(fraction: nil)), at: 3)
        precondition(quick.announcement() == "Looking Up Public IP…", "The same progress run again is announced again")

        var secret = IslandNoticeQueue()
        secret.post(IslandNotice(id: "w", text: "Copied “Home”: hunter2", spokenText: "Copied Wi-Fi password"), at: 0)
        precondition(secret.notice?.text == "Copied “Home”: hunter2" && secret.announcement() == "Copied Wi-Fi password",
                     "A notice with spoken text shows its text and announces the spoken text")
        secret.post(IslandNotice(id: "p", text: "Copied 1.2.3.4"), at: 0)
        precondition(secret.notice?.spoken == "Copied 1.2.3.4" && secret.announcement() == "Copied 1.2.3.4",
                     "A notice without spoken text announces its text")

        let clamped = IslandSwatch(red: 2, green: -1, blue: .nan)
        precondition(clamped.red == 1 && clamped.green == 0 && clamped.blue == 0,
                     "A swatch clamps each channel to 0...1 and reads a non-finite one as 0")
        let blue = IslandNotice(id: "pick", symbol: "eyedropper", text: "#12ABEF",
                                swatch: IslandSwatch(red: 0.07, green: 0.67, blue: 0.94))
        var white = blue
        white.text = "#FFFFFF"
        white.swatch = IslandSwatch(red: 1, green: 1, blue: 1)
        var picks = IslandNoticeQueue()
        picks.post(blue, at: 0)
        picks.post(white, at: 1)
        precondition(blue != white && picks.notice?.swatch == white.swatch,
                     "A repost with a new swatch shows the new swatch on top")
        dictation()
        print("IslandNoticeTest passed")
    }

    /// The dictation shapes: one live notice id reposted as its state changes (#960).
    static func dictation() {
        func recording(_ readout: String, _ meter: [Double]) -> IslandNotice {
            IslandNotice(id: "dictation", symbol: "mic", text: "Return to Paste · Esc to Cancel",
                         progress: IslandProgress(fraction: nil, readout: readout), meter: meter)
        }
        var queue = IslandNoticeQueue()
        queue.post(recording("0:00", [0]), at: 0)
        precondition(queue.notice?.isHeadline == true && near(queue.remaining(at: 1), 1.4)
                     && queue.announcement() == "Return to Paste · Esc to Cancel",
                     "Recording headlines once, for one message dwell, and is announced as it starts")
        queue.post(recording("0:01", [0.4, 0.9]), at: 1)
        precondition(near(queue.remaining(at: 1), 1.4) && queue.announcement() == nil
                     && queue.notice?.progress?.readout == "0:01" && queue.notice?.meter == [0.4, 0.9],
                     "A tick or a level reposts in place: same headline time, no new announcement")
        queue.expire(at: 2.4)
        precondition(queue.notice?.isHeadline == false && queue.remaining(at: 60) == nil,
                     "After its headline, recording stays compact until it changes")
        queue.post(recording("0:09", [0.2]), at: 9)
        precondition(queue.notice?.isHeadline == false && queue.announcement() == nil, "A later tick stays compact")
        let transcribing = IslandNotice(id: "dictation", symbol: "waveform", text: "Transcribing",
                                        progress: IslandProgress(fraction: nil, headline: false))
        queue.post(transcribing, at: 10)
        precondition(queue.notice?.isHeadline == false && queue.remaining(at: 60) == nil
                     && queue.notice?.meter == nil && queue.announcement() == nil,
                     "Transcribing stays compact on the same id, without bars, and is not announced again")
        var cleaning = transcribing
        cleaning.symbol = "sparkles"
        cleaning.text = "Cleaning Up"
        queue.post(cleaning, at: 11)
        precondition(queue.notice?.isHeadline == false && queue.remaining(at: 60) == nil,
                     "Cleaning up stays compact on the same id")
        let pasted = IslandNotice(id: "dictation", symbol: "checkmark", text: "Pasted", quiet: true)
        queue.post(pasted, at: 12)
        precondition(near(queue.remaining(at: 13), 1.4) && queue.announcement() == "Pasted" && !pasted.isHeadline,
                     "The result dwells 2.4 s, is announced once, and a quiet one keeps beside the notch")
        queue.expire(at: 14.4)
        precondition(queue.notice == nil, "The result leaves after its dwell")
        queue.post(IslandNotice(id: "dictation", symbol: "exclamationmark.triangle", text: "Dictation Failed",
                                isFailure: true), at: 20)
        precondition(near(queue.remaining(at: 21), 3) && queue.announcement() == "Dictation Failed",
                     "A failure dwells 4 s and is announced once")
        queue.post(recording("0:00", [0]), at: 30)
        queue.end("dictation", at: 31)
        precondition(queue.notice == nil, "Cancel ends the notice at once")

        let bare = IslandNotice(id: "r", text: "", progress: IslandProgress(readout: "0:07"))
        let empty = IslandNotice(id: "r", text: "Saved", progress: IslandProgress(readout: ""))
        precondition(recording("0:07", []).line == "0:07  Return to Paste · Esc to Cancel" && pasted.line == "Pasted"
                     && bare.line == "0:07" && empty.line == "Saved",
                     "The readout leads the text by two spaces, stands alone, and an empty one is none")
        precondition(IslandProgress.shape(of: "8:54") == "0:00" && IslandProgress.shape(of: "10:00") == "00:00",
                     "A readout's shape counts every digit as 0")
        precondition(IslandNotice.bars([0, 0.5, 1, 0.25, 2, .nan], count: 4, floor: 0.2) == [0.2, 1, 0.4, 0.2]
                     && IslandNotice.bars([-1, 2, 0.25, 0], count: 4, floor: 0.2) == [0.2, 1, 0.4, 0.2]
                     && IslandNotice.bars([], count: 4, floor: 0.2) == [0.2, 0.2, 0.2, 0.2],
                     "Four bars sample six levels evenly, clamp them, and rest on the floor")
        var hovered = pasted
        hovered.quiet = false
        precondition(hovered.isHeadline && !IslandNotice(id: "q", text: "x", quiet: true).isHeadline,
                     "Only the quiet flag keeps a plain notice beside the notch")
        keyLease()
    }

    /// #960: a forgotten `releaseKeys()` ends with the notice the hold was taken under.
    private static func keyLease() {
        var queue = IslandNoticeQueue()
        var lease = IslandKeyLease()
        queue.post(IslandNotice(id: "dictation", text: "Recording"), at: 0)
        lease.take(during: queue.notice?.id)
        queue.post(IslandNotice(id: "copied", text: "Copied"), at: 1)
        queue.post(IslandNotice(id: "dictation", text: "Recording 0:01"), at: 1)
        precondition(!lease.outlived(live: queue.holds) && lease.held && lease.owner == "dictation",
                     "A notice over it or a repost of its own keeps the hold")
        queue.end("dictation", at: 2)
        precondition(lease.outlived(live: queue.holds) && lease == IslandKeyLease(),
                     "Ending the notice it was taken under gives the keys back")
        precondition(!lease.outlived(live: queue.holds), "A given-back hold is not given back twice")
        lease.take(during: nil)
        precondition(!lease.outlived(live: queue.holds) && lease.held,
                     "A hold taken under no notice waits for nil")
        lease.give()
        precondition(lease == IslandKeyLease(), "nil, as after focus leaves, clears the hold and its owner")
    }

    private static func near(_ value: TimeInterval?, _ expected: TimeInterval) -> Bool {
        value.map { abs($0 - expected) < 1e-9 } ?? false
    }
}
