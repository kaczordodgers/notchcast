enum IslandMotion: Equatable {
    case open, close, fade, instant

    static func choice(opening: Bool, reduceMotion: Bool, animationsEnabled: Bool) -> Self {
        guard animationsEnabled else { return .instant }
        guard !reduceMotion else { return .fade }
        return opening ? .open : .close
    }

    var duration: Double {
        switch self {
        case .open: 0.28
        case .close: 0.20
        case .fade: 0.12
        case .instant: 0
        }
    }
}
