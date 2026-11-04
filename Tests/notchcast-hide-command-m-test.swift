// notchcast-sources: Tinycast/Features/HideCommandM/Model/HideCommandMPolicy.swift
@main
struct HideCommandMTests {
    static func main() {
        var policy = HideCommandMPolicy()
        func consume(_ down: Bool = true, code: Int64 = 46, command: Bool = true,
                     repeatKey: Bool = false, skipped: Bool = false) -> HideCommandMPolicy.Decision {
            policy.consume(keyDown: down, keyCode: code, plainCommand: command,
                           isRepeat: repeatKey, skipped: skipped)
        }
        precondition(consume(code: 45) == .pass)
        precondition(consume(command: false) == .pass)
        precondition(consume(false) == .pass)
        precondition(consume(skipped: true) == .pass)
        precondition(consume(repeatKey: true) == .pass)
        precondition(consume() == .hide)
        precondition(consume(repeatKey: true, skipped: true) == .swallow)
        precondition(consume(false, command: false) == .swallow)
        precondition(consume(false) == .pass)
        for pid: Int32 in [0, 1, 2] {
            for finder in [false, true] {
                for windows in [false, true] {
                    precondition(HideCommandMPolicy.shouldHide(pid: pid, ownPID: 1,
                        isFinder: finder, hasWindows: windows) == (pid == 2 && (!finder || windows)))
                }
            }
        }
        print("HideCommandM policy: all checks passed")
    }
}
