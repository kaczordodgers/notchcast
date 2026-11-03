import Foundation

struct SystemAudioState: Sendable, Equatable {
    struct Output: Sendable, Equatable {
        let device: UInt32
        let volume: Double?
        let muted: Bool?

        var notice: LevelNotice { .init(kind: .volume, level: volume, muted: muted) }
    }

    struct Microphone: Sendable, Equatable {
        let device: UInt32
        let muted: Bool?
    }

    var output: Output?
    var microphone: Microphone?

    func changes(from previous: Self) -> [LevelNotice] {
        var notices: [LevelNotice] = []
        if let output, let old = previous.output, output.device == old.device {
            let volumeChanged = output.volume != nil && old.volume != nil && output.volume != old.volume
            let muteChanged = output.muted != nil && old.muted != nil && output.muted != old.muted
            if volumeChanged || muteChanged { notices.append(output.notice) }
        }
        if let microphone, let old = previous.microphone, microphone.device == old.device,
           let muted = microphone.muted, old.muted != nil, old.muted != muted {
            notices.append(.init(kind: .microphone, level: nil, muted: muted))
        }
        return notices
    }
}
