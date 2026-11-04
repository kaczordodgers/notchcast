enum KatanaChannel: UInt8, CaseIterable, Sendable {
    case panel = 0, a1 = 1, a2 = 2, b1 = 5, b2 = 6

    var title: String {
        switch self {
        case .panel: "Panel"
        case .a1: "A1"
        case .a2: "A2"
        case .b1: "B1"
        case .b2: "B2"
        }
    }
}
