struct KatanaAudioSettings: Equatable, Sendable {
    let toEffectDecibels: Int
    let effectOutput: Int
    let mix: Int
    let loopback: Bool
    let dryOutput: Int

    init(toEffectDecibels: Int, effectOutput: Int, mix: Int, loopback: Bool, dryOutput: Int) throws {
        guard (-20...20).contains(toEffectDecibels), (0...100).contains(effectOutput),
              (0...100).contains(mix), (0...100).contains(dryOutput) else { throw KatanaError.invalidData }
        self.toEffectDecibels = toEffectDecibels
        self.effectOutput = effectOutput
        self.mix = mix
        self.loopback = loopback
        self.dryOutput = dryOutput
    }

    init(bytes: [UInt8]) throws {
        guard bytes.count == 5, bytes[3] <= 1 else { throw KatanaError.invalidData }
        try self.init(toEffectDecibels: Int(bytes[0]) - 20, effectOutput: Int(bytes[1]),
                      mix: Int(bytes[2]), loopback: bytes[3] == 1, dryOutput: Int(bytes[4]))
    }

    var bytes: [UInt8] {
        [UInt8(toEffectDecibels + 20), UInt8(effectOutput), UInt8(mix), loopback ? 1 : 0, UInt8(dryOutput)]
    }
}
