import Foundation

@MainActor
protocol TreadmillTransport: AnyObject {
    var onBytes: ((Data) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    func open() throws
    func send(_ data: Data) throws
    func close()
}
