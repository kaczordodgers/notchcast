import Foundation

struct FinderShortcutPolicy: Sendable {
    struct Modifiers: OptionSet, Sendable {
        let rawValue: UInt8
        static let command = Self(rawValue: 1)
        static let option = Self(rawValue: 2)
        static let control = Self(rawValue: 4)
        static let shift = Self(rawValue: 8)
        static let hyper: Self = [.command, .option, .control, .shift]
    }

    enum Action: Sendable, Equatable {
        case cut, paste, rename, forget
    }

    enum Decision: Sendable, Equatable {
        case pass, swallow, perform(Action)
    }

    struct Event: Sendable {
        let keyCode: Int64
        let modifiers: Modifiers
        var isKeyDown = true
        var isRepeat = false
        var isSynthetic = false
    }

    var cutEnabled = false
    var renameEnabled = false
    private(set) var hasCut = false
    private var pasteRequested = false
    private var swallowed: Set<Int64> = []

    mutating func decide(_ event: Event, inFinder: Bool) -> Decision {
        guard !event.isSynthetic else { return .pass }
        if !event.isKeyDown {
            return swallowed.remove(event.keyCode) == nil ? .pass : .swallow
        }
        if swallowed.contains(event.keyCode) { return .swallow }
        guard !event.isRepeat else { return .pass }
        if (event.keyCode == 8 && event.modifiers == .command)
            || (event.keyCode == 53 && event.modifiers.isEmpty) {
            guard hasCut else { return .pass }
            forget()
            return .perform(.forget)
        }
        guard inFinder else { return .pass }
        let action: Action
        switch (event.keyCode, event.modifiers) {
        case (7, .command) where cutEnabled:
            hasCut = true
            pasteRequested = false
            action = .cut
        case (9, .command) where cutEnabled && hasCut && !pasteRequested:
            pasteRequested = true
            action = .paste
        case (15, .hyper) where renameEnabled:
            action = .rename
        default:
            return .pass
        }
        swallowed.insert(event.keyCode)
        return .perform(action)
    }

    mutating func forget() {
        hasCut = false
        pasteRequested = false
    }

    mutating func restoreCut() { pasteRequested = false }

    mutating func reset() {
        forget()
        swallowed.removeAll()
    }
}
