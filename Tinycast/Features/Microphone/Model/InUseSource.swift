import Foundation

@MainActor
protocol InUseSource: AnyObject {
    var monitoringFailure: MicrophoneInput.Failure? { get }
    func start(change: @escaping @MainActor () -> Void)
    func stop()
    func read() throws(MicrophoneInput.Failure) -> InUseReading
}
