import Foundation

nonisolated enum KatanaGen3Defaults {
    private static let text: [UInt8: String] = {
        let effect = """
            01013223230032012332323C0032006400646400003232323200001E0B0A1E141414141414141414141400140D0114170114140E1400
            323232322D323C00281E2832321900003E640001183C000000004601182800000000460064010C000000004607000000005000641818
            181818181818181818181818181818181818181818180132321032323200462837000064001F285232003C0046554132553C32463C64
            0032323200502D32003264640100023250643264042B2E034B21300341503232323201322D3232506400646400003232000109003264
            320032006424326400
            """
        let delayTail = "00010900160A32643228370100000000"
        let reverbTail = "021D0000000A0E0808236464"
        let eq = "00140E0114170114140E14"
        var map: [UInt8: String] = [
            0x00: "4B4154414E4120202020202020202020", 0x02: "020100", 0x04: "0000000000", 0x06: "32323232323200013200",
            0x08: "000000000000", 0x0A: "09323C3200322800", 0x0C: "0A323C3200322800", 0x0E: "0D323C3200322800",
            0x10: "17", 0x12: "19", 0x14: "1A", 0x16: "10", 0x18: "00", 0x1A: "1D",
            0x3A: "0032", 0x3C: "000000180D0118180E18", 0x3E: "000100010900163264000A002837", 0x40: "00",
            0x42: "0032", 0x44: "0132", 0x46: "0232", 0x48: "000000", 0x4A: "006400646400243264006400646400",
            0x4C: "000000", 0x4E: "010000", 0x50: eq, 0x52: eq, 0x54: String(repeating: "18", count: 11),
            0x56: String(repeating: "18", count: 11), 0x58: "000532", 0x5A: "0100003232",
            0x5E: "02", 0x66: "0001",
        ]
        for region in stride(from: 0x1C, through: 0x26, by: 2) { map[UInt8(region)] = effect }
        for (index, region) in stride(from: 0x28, through: 0x32, by: 2).enumerated() {
            map[UInt8(region)] = ["00", "03", "04"][index % 3] + delayTail
        }
        for (index, region) in stride(from: 0x34, through: 0x38, by: 2).enumerated() {
            map[UInt8(region)] = ["00", "03", "02"][index] + reverbTail
        }
        return map
    }()

    static func image() -> [UInt8: [UInt8]] {
        var image: [UInt8: [UInt8]] = [:]
        for region in KatanaPatchRegion.all {
            let bytes = KatanaLegacyFormats.decode(text[region.region] ?? "")
            image[region.region] = bytes + [UInt8](repeating: 0, count: max(0, region.length - bytes.count))
        }
        return image
    }
}
