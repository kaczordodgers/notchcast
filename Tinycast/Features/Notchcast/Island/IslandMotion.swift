enum IslandMotion: Equatable {
    case open, close, fade, instant

    static func choice(opening: Bool, reduceMotion: Bool, animationsEnabled: Bool) -> Self {
        guard animationsEnabled else { return .instant }
        guard !reduceMotion else { return .fade }
        return opening ? .open : .close
    }

    /// A perceptual spring for the silhouette's morph (`CASpringAnimation(perceptualDuration:bounce:)`).
    struct Spring: Equatable {
        let duration: Double
        let bounce: Double
    }

    /// Growing sides overshoot a little and settle; shrinking ones never swing (after Vorssaint's notch).
    static let growWidth = Spring(duration: 0.44, bounce: 0.25)
    static let growHeight = Spring(duration: 0.38, bounce: 0.22)
    static let shrinkWidth = Spring(duration: 0.30, bounce: 0)
    static let shrinkHeight = Spring(duration: 0.26, bounce: 0)

    var duration: Double {
        switch self {
        case .open: 0.28
        case .close: 0.20
        case .fade: 0.12
        case .instant: 0
        }
    }
}
