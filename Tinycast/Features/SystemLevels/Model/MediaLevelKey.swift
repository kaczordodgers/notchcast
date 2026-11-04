import Foundation

enum MediaLevelKey: Int, CaseIterable, Sendable {
    case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7

    var isBrightness: Bool { self == .brightnessUp || self == .brightnessDown }
    var isIncreasing: Bool { self == .volumeUp || self == .brightnessUp }
}
