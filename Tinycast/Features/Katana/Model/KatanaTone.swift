import Foundation

struct KatanaTone: Codable, Equatable, Sendable {
    struct Region: Codable, Equatable, Sendable {
        let region: UInt8
        let bytes: [UInt8]
    }

    let name: String
    let comment: String
    let regions: [Region]
    let knob: [UInt8]
    let knobSolo: [UInt8]
    let converted: Bool

    init(regions: [Region], knob: [UInt8], knobSolo: [UInt8], comment: String = "", converted: Bool = false) throws {
        let present = Set(regions.map(\.region))
        guard KatanaPatchRegion.essential.isSubset(of: present), present.count == regions.count,
              knob.count == 5, knobSolo.count == 1, (knob + knobSolo).allSatisfy({ $0 < 0x80 }),
              regions.allSatisfy({ region in
                  guard let known = KatanaPatchRegion.all.first(where: { $0.region == region.region }) else { return false }
                  return region.bytes.count == known.length && region.bytes.allSatisfy { $0 < 0x80 }
              }), let nameBytes = regions.first(where: { $0.region == 0 })?.bytes else {
            throw KatanaError.invalidData
        }
        let name = KatanaSysEx.name(nameBytes)
        guard !name.isEmpty else { throw KatanaError.invalidData }
        self.name = name
        self.comment = comment
        var image = KatanaGen3Defaults.image()
        for region in regions { image[region.region] = region.bytes }
        self.regions = KatanaPatchRegion.all.map { Region(region: $0.region, bytes: image[$0.region]!) }
        self.knob = knob
        self.knobSolo = knobSolo
        self.converted = converted
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(regions: container.decode([Region].self, forKey: .regions),
                      knob: container.decode([UInt8].self, forKey: .knob),
                      knobSolo: container.decode([UInt8].self, forKey: .knobSolo),
                      comment: container.decode(String.self, forKey: .comment),
                      converted: container.decode(Bool.self, forKey: .converted))
    }
}
