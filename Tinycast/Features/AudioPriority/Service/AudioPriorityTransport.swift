import Foundation

@MainActor
protocol AudioPriorityTransport: AnyObject {
    func devices() throws -> [AudioPriorityDevice]
    func defaultUID(for direction: AudioPriorityDevice.Direction) throws -> String?
    func setDefault(uid: String, for direction: AudioPriorityDevice.Direction) throws
    func start(onChange: @escaping @Sendable () -> Void) throws
    func stop() throws
}
