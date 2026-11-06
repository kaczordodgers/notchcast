import QuartzCore

/// How the silhouette moves from one outline to the next.
enum IslandMotion: Equatable {
    /// Closed to open, and into the launcher: a large shape, so it never swings.
    case open
    /// A closed state widening or a bubble beading out, on the opening's spring.
    case grow
    /// Back to rest: open to closed, a closed state narrowing, a launcher that left mid-opening.
    case shrink
    /// Reduce Motion: the whole island cross-fades, nothing moves.
    case fade
    case instant

    static func choice(from: IslandOutline?, to: IslandOutline, opening: Bool, reduceMotion: Bool,
                       animationsEnabled: Bool) -> Self {
        guard animationsEnabled else { return .instant }
        guard !reduceMotion else { return .fade }
        if opening { return .open }
        guard let from else { return .shrink }
        return to.bounds.width * to.bounds.height > from.bounds.width * from.bounds.height ? .grow : .shrink
    }

    /// A perceptual spring for the silhouette's morph (`CASpringAnimation(perceptualDuration:bounce:)`).
    struct Spring: Equatable {
        let duration: Double
        let bounce: Double

        var animation: CASpringAnimation { CASpringAnimation(perceptualDuration: duration, bounce: bounce) }

        /// Progress from 0 to 1 at each time, from the animation's own mass, stiffness and damping, starting at rest.
        func curve() -> (Double) -> Double {
            let spring = animation
            let omega = (Double(spring.stiffness) / Double(spring.mass)).squareRoot()
            let zeta = Double(spring.damping) / (2 * (Double(spring.stiffness) * Double(spring.mass)).squareRoot())
            if abs(zeta - 1) < 1e-6 {
                return { time in 1 - exp(-omega * max(0, time)) * (1 + omega * max(0, time)) }
            }
            if zeta < 1 {
                let damped = omega * (1 - zeta * zeta).squareRoot()
                return { time in
                    let t = max(0, time)
                    return 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
                }
            }
            let root = omega * (zeta * zeta - 1).squareRoot()
            let fast = -zeta * omega - root, slow = -zeta * omega + root
            return { time in
                let t = max(0, time)
                return 1 - (fast * exp(slow * t) - slow * exp(fast * t)) / (fast - slow)
            }
        }

        /// The first moment the spring reaches `progress`, to the millisecond.
        func time(reaching progress: Double) -> Double {
            let curve = curve()
            let limit = Double(animation.settlingDuration)
            var time = 0.0
            while curve(time) < progress, time < limit { time += 0.001 }
            return min(time, limit)
        }
    }

    /// No island spring bounces: its one outline carries the row that meets the notch, and an overshoot would show the
    /// screen behind it. `Theme.Duration.settingsReveal` and `Theme.Duration.enter`; back to rest is the quicker.
    static let growing = Spring(duration: 0.28, bounce: 0)
    static let shrinking = Spring(duration: 0.18, bounce: 0)

    var spring: Spring? {
        switch self {
        case .open, .grow: Self.growing
        case .shrink: Self.shrinking
        case .fade, .instant: nil
        }
    }

    /// Content and Reduce Motion cross-fades; the morph itself runs for its spring's settling time.
    static let crossFade = 0.12
}
