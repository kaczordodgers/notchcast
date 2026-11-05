// notchcast-sources: Tinycast/Features/SystemLevels/Model/MediaLevelKey.swift
// notchcast-sources: Tinycast/Features/SystemLevels/Model/MediaLevelKeyPolicy.swift
import Foundation

@main
struct BrightnessKeysTest {
    static func main() {
        let enabled: Set<MediaLevelKey> = [.brightnessDown, .brightnessUp]
        for (code, key) in [(145, MediaLevelKey.brightnessDown), (144, .brightnessUp)] {
            var policy = MediaLevelKeyPolicy()
            precondition(policy.decide(keyCode: code, isDown: true, isRepeat: false,
                                       modifiers: 0, enabled: []) == .pass)
            precondition(policy.decide(keyCode: code, isDown: true, isRepeat: false,
                                       modifiers: 0x100000, enabled: enabled) == .pass)
            for modifiers: UInt64 in [0, 0xA0000] {
                let expected = MediaLevelKeyPolicy.Decision.press(key, fine: modifiers != 0)
                precondition(policy.decide(keyCode: code, isDown: true, isRepeat: false,
                                           modifiers: modifiers, enabled: enabled) == expected)
                precondition(policy.decide(keyCode: code, isDown: true, isRepeat: true,
                                           modifiers: modifiers, enabled: enabled) == expected)
                precondition(policy.decide(keyCode: code, isDown: false, isRepeat: false,
                                           modifiers: modifiers, enabled: enabled) == .swallow)
                precondition(policy.decide(subtype: 8, data: (key.rawValue << 16) | 0xA00,
                                           modifiers: modifiers, enabled: enabled) == expected)
                precondition(policy.decide(subtype: 8, data: (key.rawValue << 16) | 0xB00,
                                           modifiers: modifiers, enabled: enabled) == .swallow)
            }
        }
        print("PASS: brightness media/keycode presses, repeats, releases, fine and disabled decisions")
    }
}
