// notchcast-sources: Tinycast/Features/Distill/Model/DistillAudioChunks.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationAudioChunks.swift
import Foundation

enum DictationWire {
    static let sampleRate = 8_000
}

@main
struct DistillRateTest {
    static func main() {
        precondition(DistillAudioChunks.maximumSamples == DictationWire.sampleRate * 240)
        let chunk = DistillAudioChunks.Chunk(offset: 10_000, count: 4_000)
        precondition(chunk.start == 1.25)
        print("Verified: Distill chunk limits and timestamps follow the wire sample rate")
    }
}
