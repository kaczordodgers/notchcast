import Foundation

enum KatanaToneImporter {
    static let maximumBytes = 16 * 1024 * 1024

    static func read(_ data: Data, fileExtension: String) throws -> [KatanaTone] {
        guard !data.isEmpty, data.count <= maximumBytes else { throw KatanaError.invalidData }
        switch fileExtension.lowercased() {
        case "json": return [try KatanaPresetImporter.read(data)]
        case "tsl": return try liveset(data)
        case "kat3":
            let image = try image(data, size: 73728)
            let regions = KatanaPatchRegion.all.map { known in
                let start = Int(known.region) << 7
                return KatanaTone.Region(region: known.region, bytes: Array(image[start..<(start + known.length)]))
            }
            let knobStart = (1 << 14) + (0x1C << 7)
            let soloStart = (1 << 14) + (0x1E << 7)
            return [try KatanaTone(regions: regions, knob: Array(image[knobStart..<(knobStart + 5)]),
                                   knobSolo: [image[soloStart]])]
        case "kat2":
            return [try convert(KatanaLegacyFormats.kat2(Data(try image(data, size: 1992))))]
        case "kat":
            return [try convert(KatanaLegacyFormats.kat(Data(try image(data, size: 2797))))]
        default: throw KatanaError.unsupportedFormat
        }
    }

    private static func image(_ data: Data, size: Int) throws -> [UInt8] {
        guard data.count == size, data.dropFirst(16).allSatisfy({ $0 < 0x80 }) else { throw KatanaError.invalidData }
        var bytes = [UInt8](data)
        for index in 0..<16 where !(0x20...0x7E).contains(bytes[index]) { bytes[index] = 0x20 }
        return bytes
    }

    private static func liveset(_ data: Data) throws -> [KatanaTone] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = object["device"] as? String else { throw KatanaError.invalidData }
        if device == "GT" {
            guard let patches = object["patchList"] as? [[String: Any]], !patches.isEmpty else {
                throw KatanaError.invalidData
            }
            return try patches.map { patch in
                guard let params = patch["params"] as? [String: Any] else { throw KatanaError.invalidData }
                return try convert(KatanaLegacyFormats.mk1(params: params, comment: memo(patch["note"])))
            }
        }
        guard device == "KATANA Gen3" || device == "KATANA MkII" else { throw KatanaError.unsupportedFormat }
        guard let groups = object["data"] as? [[[String: Any]]], groups.count == 1,
              let patches = groups.first, !patches.isEmpty else { throw KatanaError.invalidData }
        return try patches.map { patch in
            guard let parameters = patch["paramSet"] as? [String: Any] else { throw KatanaError.invalidData }
            if device == "KATANA MkII" {
                return try convert(KatanaLegacyFormats.mk2(paramSet: parameters,
                    revision: object["formatRev"] as? String, comment: memo(patch["memo"])))
            }
            var regions: [KatanaTone.Region] = []
            for known in KatanaPatchRegion.all {
                guard let value = parameters["PATCH%\(known.block)"] else { continue }
                let bytes = try hex(value)
                regions.append(.init(region: known.region, bytes: Array(bytes.prefix(known.length))))
            }
            let knob = try hex(parameters["PATCH%PATCH_KNOB_READONLY"] ?? ["00", "00", "00", "00", "00"])
            let solo = try hex(parameters["PATCH%PATCH_KNOB_SOLO_DELAY_READONLY"] ?? ["00"])
            return try KatanaTone(regions: regions, knob: knob, knobSolo: solo, comment: memo(patch["memo"]))
        }
    }

    private static func convert(_ patch: KatanaLegacyPatch?) throws -> KatanaTone {
        guard let patch, patch.blocks.values.joined().allSatisfy({ $0 < 0x80 }),
              let converted = KatanaLegacyConverter.convert(patch) else { throw KatanaError.invalidData }
        return try KatanaTone(regions: converted.regions, knob: converted.knob, knobSolo: [0],
                              comment: patch.comment, converted: true)
    }

    private static func hex(_ value: Any) throws -> [UInt8] {
        guard let list = value as? [String] else { throw KatanaError.invalidData }
        return try list.map { text in
            guard text.count == 2, let byte = UInt8(text, radix: 16), byte < 0x80 else { throw KatanaError.invalidData }
            return byte
        }
    }

    private static func memo(_ value: Any?) -> String {
        var current = value
        while let nested = current as? [String: Any] { current = nested["memo"] }
        return current as? String ?? ""
    }
}
