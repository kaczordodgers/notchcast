// notchcast-sources: Tinycast/Features/FinderTools/Model/*.swift
// notchcast-sources: Tinycast/Features/FinderTools/Service/FinderShortcutState.swift
import Foundation

@main
struct FinderToolsPolicyTest {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        typealias Event = FinderShortcutPolicy.Event
        var policy = FinderShortcutPolicy()
        let cut = Event(keyCode: 7, modifiers: .command)
        let paste = Event(keyCode: 9, modifiers: .command)
        let copy = Event(keyCode: 8, modifiers: .command)
        let escape = Event(keyCode: 53, modifiers: [])
        let rename = Event(keyCode: 15, modifiers: .hyper)
        check(policy.decide(cut, inFinder: true) == .pass, "Disabled cut is untouched")
        check(policy.decide(rename, inFinder: true) == .pass, "Disabled rename is untouched")
        policy.cutEnabled = true
        policy.renameEnabled = true
        check(policy.decide(cut, inFinder: false) == .pass, "Cut belongs only to Finder")
        check(policy.decide(rename, inFinder: false) == .pass, "Rename belongs only to Finder")
        check(policy.decide(paste, inFinder: true) == .pass, "Ordinary paste is untouched")
        for raw in UInt8(0)..<16 where raw != 1 {
            check(policy.decide(Event(keyCode: 7, modifiers: .init(rawValue: raw)), inFinder: true) == .pass,
                  "Other modifier combinations are untouched")
        }
        check(policy.decide(cut, inFinder: true) == .perform(.cut), "Command-X captures cut")
        check(policy.decide(Event(keyCode: 7, modifiers: .command, isRepeat: true), inFinder: true) == .swallow,
              "Held cut does not repeat")
        check(policy.decide(Event(keyCode: 7, modifiers: [], isKeyDown: false), inFinder: false) == .swallow,
              "A consumed key-up stays consumed across an app or modifier change")
        check(policy.decide(Event(keyCode: 7, modifiers: [], isKeyDown: false), inFinder: true) == .pass,
              "A consumed key-up is released once")
        check(policy.decide(paste, inFinder: true) == .perform(.paste), "Cut turns paste into move")
        check(policy.decide(escape, inFinder: false) == .perform(.forget), "Escape cancels even a queued move")
        check(!policy.hasCut, "Escape clears pending cut")
        policy.reset()
        _ = policy.decide(cut, inFinder: true)
        check(policy.decide(copy, inFinder: false) == .perform(.forget), "Copy in another app cancels")
        check(policy.decide(rename, inFinder: true) == .perform(.rename), "Hyper-R starts rename")
        check(policy.decide(Event(keyCode: 15, modifiers: .hyper, isRepeat: true), inFinder: true) == .swallow,
              "Rename is not repeated")
        policy.reset()
        check(policy.decide(Event(keyCode: 7, modifiers: .command, isRepeat: true), inFinder: true) == .pass,
              "An unowned repeat is untouched")
        check(policy.decide(Event(keyCode: 7, modifiers: .command, isSynthetic: true), inFinder: true) == .pass,
              "Tagged synthetic input cannot reenter")

        var session = FinderCutSession()
        check(!session.take(changeCount: 1), "No cut never moves")
        session.mark(changeCount: 3, fileCount: 2)
        check(session.fileCount == 2, "Cut exposes its count without a view")
        check(!session.take(changeCount: 4), "Another clipboard write invalidates cut")
        check(session.fileCount == 0 && session.clipboardChangeCount == nil, "Invalid cuts are cleared")
        session.mark(changeCount: 4, fileCount: 2)
        check(session.take(changeCount: 4), "The same clipboard moves once")
        check(!session.take(changeCount: 4), "A second paste cannot move twice")
        session.mark(changeCount: 5, fileCount: 0)
        check(!session.take(changeCount: 5), "A non-file clipboard never moves")
        session.mark(changeCount: 6, fileCount: 1)
        session.clear()
        check(!session.take(changeCount: 6), "Disabling forgets the cut")

        let state = FinderShortcutState()
        state.configure(cut: true, rename: true, pid: 42)
        let (_, first) = state.receive(cut)
        check(first != nil && state.isCurrent(first!), "Captured operations carry an identity")
        _ = state.receive(Event(keyCode: 7, modifiers: [], isKeyDown: false))
        let (_, second) = state.receive(cut)
        check(!state.isCurrent(first!) && state.isCurrent(second!), "A new cut invalidates suspended work")
        _ = state.receive(copy)
        check(!state.isCurrent(second!), "Copy invalidates suspended work immediately")
        _ = state.receive(Event(keyCode: 7, modifiers: [], isKeyDown: false))
        let (_, third) = state.receive(cut)
        state.setFrontmostFinder(nil)
        state.setFrontmostFinder(42)
        check(!state.isCurrent(third!), "Switching away and back cannot revive suspended work")
        state.configure(cut: true, rename: true, pid: 42)
        let (_, fourth) = state.receive(cut)
        state.configure(cut: false, rename: true, pid: 42)
        check(!state.isCurrent(fourth!), "Stopping a module invalidates its work")
        check(state.receive(cut).0 == .pass, "Stopping cut leaves rename independent")
        check(state.receive(rename).0 == .perform(.rename), "Rename remains enabled independently")
        state.configure(cut: true, rename: false, pid: 42)
        let (_, fifth) = state.receive(cut)
        _ = state.receive(Event(keyCode: 7, modifiers: [], isKeyDown: false))
        let (_, move) = state.receive(paste)
        state.finishCut(fourth!)
        check(state.isCurrent(fifth!), "A stale completion cannot clear a newer cut")
        state.restoreCut(move!)
        _ = state.receive(Event(keyCode: 9, modifiers: [], isKeyDown: false))
        check(state.receive(paste).0 == .perform(.paste), "Pasting text can preserve the file cut")
        state.finishCut(fifth!)
        _ = state.receive(Event(keyCode: 9, modifiers: [], isKeyDown: false))
        check(state.receive(paste).0 == .pass, "A completed move restores normal paste")
        print("PASS: \(checks) Finder policy and operation identity checks; no system state changed")
    }
}
