import Foundation

nonisolated enum KatanaLegacyFormats {
    static let kat2Size = 1992
    static let katSize = 2797
    private static let chainBlock = KatanaMkIIBlock.patch2
    private static let chainValues = [0, 1, 3]

    static func kat2(_ data: Data) -> KatanaLegacyPatch? {
        guard data.count == kat2Size else { return nil }
        let bytes = [UInt8](data)
        var blocks: [KatanaMkIIBlock: [UInt8]] = [:]
        for block in KatanaMkIIBlock.allCases { blocks[block] = Array(bytes[block.fileOffset..<block.fileOffset + block.size]) }
        return KatanaLegacyPatch(blocks: blocks)
    }

    static func mk2(paramSet: [String: Any], revision: String?, comment: String) -> KatanaLegacyPatch? {
        var blocks: [KatanaMkIIBlock: [UInt8]] = [:]
        for block in KatanaMkIIBlock.allCases {
            guard let list = paramSet[block.key] as? [String] else { continue }
            guard let bytes = hex(list) else { return nil }
            blocks[block] = bytes
        }
        if revision == "0000", let first = blocks[.patch1], first.count > 0x60 {
            blocks[.patch2] = Array(first[0x60...])
            blocks[.patch1] = Array(first[..<0x32])
        }
        guard blocks[.name]?.count == KatanaMkIIBlock.name.size,
              blocks[.patch0]?.count == KatanaMkIIBlock.patch0.size,
              blocks[.patch2]?.count == KatanaMkIIBlock.patch2.size else { return nil }
        return KatanaLegacyPatch(blocks: blocks, comment: comment)
    }

    static func mk1(params: [String: Any], comment: String) -> KatanaLegacyPatch? {
        guard (1...16).allSatisfy({ params["patch_name\($0)"] != nil }) else { return nil }
        var blocks = factory
        for (name, value) in params {
            guard let place = nameIndex[name] else { continue }
            guard let number = integer(value), (0..<0x80).contains(number) else { return nil }
            blocks[place.block]?[place.offset] = UInt8(number)
        }
        return finishMk1(blocks, comment: comment)
    }

    static func kat(_ data: Data) -> KatanaLegacyPatch? {
        guard data.count == katSize else { return nil }
        let bytes = [UInt8](data)
        var blocks = factory
        for run in KatanaMk1Data.fileRuns {
            for step in 0..<run.count { blocks[run.block]?[run.first + step] = bytes[run.file + step] }
        }
        return finishMk1(blocks, comment: "")
    }

    private static func finishMk1(_ blocks: [KatanaMkIIBlock: [UInt8]], comment: String) -> KatanaLegacyPatch? {
        var blocks = blocks
        guard let pattern = blocks[chainBlock]?[0], Int(pattern) < chainValues.count else { return nil }
        blocks[chainBlock]?[0] = UInt8(chainValues[Int(pattern)])
        blocks[.status]?[1] = blocks[.patch0]?[18] ?? 50
        return KatanaLegacyPatch(blocks: blocks, comment: comment)
    }

    private static let factory: [KatanaMkIIBlock: [UInt8]] = KatanaMk1Data.initial.mapValues(decode)

    static func decode(_ text: String) -> [UInt8] {
        let digits = Array(text.filter { !$0.isWhitespace }.utf8)
        return stride(from: 0, to: digits.count - 1, by: 2).compactMap { offset in
            String(bytes: digits[offset...offset + 1], encoding: .utf8).flatMap { UInt8($0, radix: 16) }
        }
    }

    private static let nameIndex: [String: (block: KatanaMkIIBlock, offset: Int)] = {
        var index: [String: (block: KatanaMkIIBlock, offset: Int)] = [:]
        for (block, names) in KatanaMk1Data.names {
            for (offset, name) in names.split(whereSeparator: \.isWhitespace).enumerated() where name != "-" {
                index[String(name)] = (block, offset)
            }
        }
        return index
    }()

    private static func integer(_ value: Any) -> Int? {
        if let text = value as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
        guard let number = value as? NSNumber, String(cString: number.objCType) != "c",
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              (0..<128).contains(number.doubleValue) else { return nil }
        return number.intValue
    }

    private static func hex(_ list: [String]) -> [UInt8]? {
        var bytes: [UInt8] = []
        for item in list {
            guard let byte = UInt8(item, radix: 16), byte < 0x80 else { return nil }
            bytes.append(byte)
        }
        return bytes
    }
}
