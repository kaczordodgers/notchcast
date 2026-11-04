import Foundation

struct CleanOptimizeOutcome: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case alreadyEmpty, invalidExecutable, transportFailed, timedOut
        case exitCode(Int32), invalidRowCount, remainingRows(Int)
    }

    enum Status: Equatable, Sendable {
        case ran
        case skipped(Reason)
        case failed(Reason)
    }

    let task: CleanOptimizeTask
    let status: Status
    var ran: Bool { status == .ran }
}
