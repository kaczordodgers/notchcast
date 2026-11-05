import AppKit

/// What a key does on the open island, read from the physical key so every layout agrees.
enum IslandKey: Equatable, Sendable {
    case pin, refresh, close, activate
    case page(IslandPage)
    case header(Int)
    case selection(Int)
    /// A held chord or Return: swallowed, so one press acts once and the app behind never sees it.
    case ignored

    enum Chord: Sendable { case plain, command, shift, other }

    @MainActor init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let chord: Chord = flags.isEmpty ? .plain : flags == .command ? .command : flags == .shift ? .shift : .other
        let character = chord == .command
            ? ASCIIKeyboardLayout.character(for: event) ?? event.charactersIgnoringModifiers : nil
        guard let key = Self.resolve(keyCode: event.keyCode, chord: chord, isRepeat: event.isARepeat,
                                     character: character) else { return nil }
        self = key
    }

    /// `character` is the ASCII-layout letter under ⌘; page digits come from the number row's key codes.
    static func resolve(keyCode: UInt16, chord: Chord, isRepeat: Bool, character: String?) -> Self? {
        switch chord {
        case .command:
            let key: Self? = switch character?.lowercased() {
            case "p": .pin
            case "r": .refresh
            default: FavoriteSlots.index(forKeyCode: keyCode).flatMap(FavoriteSlots.digit(at:))
                .flatMap { IslandPage.page(forKey: String($0)) }.map(Self.page)
            }
            return isRepeat ? key.map { _ in .ignored } : key
        case .plain:
            switch keyCode {
            case 53: return isRepeat ? .ignored : .close
            case 36, 76: return isRepeat ? .ignored : .activate
            case 123: return .header(-1)
            case 124, 48: return .header(1)
            case 125: return .selection(1)
            case 126: return .selection(-1)
            default: return nil
            }
        case .shift: return keyCode == 48 ? .header(-1) : nil
        case .other: return nil
        }
    }
}
