import Foundation

@MainActor
protocol TreadmillTransport: AnyObject {
    var onBytes: ((Data) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    var onReady: (() -> Void)? { get set }
    var onFailure: (((any Error)?) -> Void)? { get set }
    var maintainsConnection: Bool { get }
    func open() throws
    func send(_ data: Data) throws
    func close()
}

extension TreadmillTransport {
    var onReady: (() -> Void)? { get { nil } set {} }
    var onFailure: (((any Error)?) -> Void)? { get { nil } set {} }
    var maintainsConnection: Bool { false }
}
