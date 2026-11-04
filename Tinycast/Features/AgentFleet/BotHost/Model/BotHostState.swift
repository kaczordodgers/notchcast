import Foundation

enum BotHostState: Sendable, Equatable {
    case done, failed, waitingForPerson, timedOut, unreachable, working

    init(exitCode: Int) {
        switch exitCode {
        case 0: self = .done
        case 3: self = .waitingForPerson
        case 4: self = .timedOut
        case 5: self = .unreachable
        default: self = .failed
        }
    }
}
