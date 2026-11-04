import Foundation

enum MachLinkRequestBudget {
    static let responder = RootContract.Operation.change.timeout * 2 + .seconds(2)
    static let requester = responder + .seconds(2)
}
