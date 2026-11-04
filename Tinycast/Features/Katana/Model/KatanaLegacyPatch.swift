nonisolated struct KatanaLegacyPatch: Sendable {
    var blocks: [KatanaMkIIBlock: [UInt8]]
    var comment = ""
}
