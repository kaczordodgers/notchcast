import Foundation

struct LevelNotice: Sendable, Equatable {
    enum Kind: Sendable { case volume, microphone, brightness }
    let kind: Kind
    let percent: Int?
    let muted: Bool?

    init(kind: Kind, level: Double?, muted: Bool? = nil) {
        self.kind = kind
        self.muted = muted
        percent = level.flatMap { $0.isFinite ? Int((min(1, max(0, $0)) * 100).rounded()) : nil }
    }

    var symbol: String {
        switch kind {
        case .brightness: "sun.max.fill"
        case .microphone: muted == true ? "mic.slash.fill" : "mic.fill"
        case .volume:
            if muted == true || percent == 0 {
                "speaker.slash.fill"
            } else if let percent, percent < 34 {
                "speaker.wave.1.fill"
            } else if let percent, percent < 67 {
                "speaker.wave.2.fill"
            } else {
                "speaker.wave.3.fill"
            }
        }
    }
}
