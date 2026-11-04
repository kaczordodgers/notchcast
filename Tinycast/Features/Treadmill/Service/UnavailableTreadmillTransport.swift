import Foundation

@MainActor
final class UnavailableTreadmillTransport: TreadmillTransport {
    var onBytes: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?

    func open() throws { throw TreadmillFailure.unavailable }
    func send(_ data: Data) throws { throw TreadmillFailure.unavailable }
    func close() {}
}
