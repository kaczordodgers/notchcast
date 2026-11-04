import Foundation

enum MachLinkRequestBudget {
    static let responder: Duration = .seconds(8)
    static let requester: Duration = .seconds(10)
}
