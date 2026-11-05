import Foundation

struct MediaLevelKeyPolicy: Sendable {
    enum Decision: Equatable {
        case pass, swallow
        case press(MediaLevelKey, fine: Bool)
    }

    private var down: Set<MediaLevelKey> = []
    private static let shortcutModifiers: UInt64 = 0x1E0000
    private static let fineModifiers: UInt64 = 0xA0000

    mutating func decide(keyCode: Int, isDown: Bool, isRepeat: Bool, modifiers: UInt64,
                         enabled: Set<MediaLevelKey>) -> Decision {
        let key: MediaLevelKey
        switch keyCode {
        case 144: key = .brightnessUp
        case 145: key = .brightnessDown
        default: return .pass
        }
        return decide(subtype: 8, data: (key.rawValue << 16) | ((isDown ? 0xA : 0xB) << 8)
            | (isRepeat ? 1 : 0), modifiers: modifiers, enabled: enabled)
    }

    mutating func decide(subtype: Int, data: Int, modifiers: UInt64,
                         enabled: Set<MediaLevelKey>) -> Decision {
        guard subtype == 8, let key = MediaLevelKey(rawValue: (data >> 16) & 0xFFFF),
              enabled.contains(key) else { return .pass }
        let state = (data >> 8) & 0xFF
        if state == 0xB { return down.remove(key) != nil ? .swallow : .pass }
        guard state == 0xA else { return .pass }
        let isRepeat = data & 1 != 0
        let relevant = modifiers & Self.shortcutModifiers
        let fine = relevant == Self.fineModifiers
        if isRepeat {
            guard down.contains(key) else { return .pass }
            return key == .mute ? .swallow : .press(key, fine: fine)
        }
        if down.contains(key) { return .swallow }
        guard relevant == 0 || fine else { return .pass }
        down.insert(key)
        return .press(key, fine: fine)
    }
}
