import Foundation

@MainActor
protocol MicrophoneAudioAccess: AnyObject {
    var monitoringFailure: MicrophoneInput.Failure? { get }
    func inputs() throws(MicrophoneInput.Failure) -> [MicrophoneInput]
    func write(_ levels: [MicrophoneInput.Level], control: MicrophoneInput.Control,
               on input: MicrophoneInput) throws(MicrophoneInput.Failure)
    func start(change: @escaping @MainActor () -> Void)
    func stop()
}
