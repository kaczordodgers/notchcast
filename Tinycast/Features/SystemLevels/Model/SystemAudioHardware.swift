import Foundation

protocol SystemAudioHardware: Sendable {
    func output() -> SystemAudioState.Output?
    func microphone() -> SystemAudioState.Microphone?
    func writeVolume(_ volume: Double, device: UInt32) -> Bool
    func writeMute(_ muted: Bool, device: UInt32) -> Bool
}
