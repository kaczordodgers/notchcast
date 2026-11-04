import Foundation

struct KatanaRecording: Equatable, Sendable {
    let wet: URL
    let dry: URL
    let sampleRate: Double
    let frames: Int

    var duration: Double { Double(frames) / sampleRate }

    struct Destination: Equatable, Sendable {
        enum Codec: Sendable { case aac, appleLossless }

        let wet: URL
        let dry: URL
        let wetInputs = [0, 1]
        let dryInput = 2
        let wetBitRate = 256_000
        let wetCodec = Codec.aac
        let dryCodec = Codec.appleLossless

        init(wet: URL, dry: URL) throws {
            guard wet.isFileURL, dry.isFileURL, wet.pathExtension.lowercased() == "m4a",
                  dry.pathExtension.lowercased() == "m4a", wet.standardizedFileURL != dry.standardizedFileURL else {
                throw KatanaError.invalidData
            }
            self.wet = wet
            self.dry = dry
        }
    }
}
