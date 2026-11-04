import Foundation

nonisolated enum KatanaLegacyConverter {
    struct Result: Sendable {
        let regions: [KatanaTone.Region]
        let knob: [UInt8]
    }

    private struct Move {
        let src: Int, dst: Int, count: Int, isWide: Bool
        static func copy(_ src: Int, _ dst: Int, _ count: Int = 1) -> Move {
            Move(src: src, dst: dst, count: count, isWide: false)
        }
        static func wide(_ src: Int, _ dst: Int) -> Move { Move(src: src, dst: dst, count: 1, isWide: true) }
    }

    private struct Plan {
        let block: KatanaMkIIBlock
        let moves: [Move]
        let regions: [UInt8]
        init(_ block: KatanaMkIIBlock, _ regions: [UInt8], _ moves: [Move]) {
            self.block = block
            self.regions = regions
            self.moves = moves
        }
    }

    private static let switches: UInt8 = 0x08, amp: UInt8 = 0x06, soloCom: UInt8 = 0x3A
    private static let contour: UInt8 = 0x40, color: UInt8 = 0x04
    private static let boosters: [UInt8] = [0x0A, 0x0C, 0x0E], reverbs: [UInt8] = [0x34, 0x36, 0x38]

    private static let effectMoves: [Move] = [
        .copy(2, 0, 76), .wide(78, 76), .copy(80, 80, 4), .wide(84, 84), .copy(86, 88, 5), .wide(91, 93), .copy(93, 97, 2),
        .wide(95, 99), .copy(97, 103, 46), .copy(144, 149, 7), .copy(153, 156), .copy(156, 157, 12), .copy(170, 169, 26),
        .copy(197, 195, 15), .wide(212, 210), .copy(214, 214, 11),
    ]
    private static let delayMoves: [Move] = [.wide(2, 1), .copy(4, 5, 5), .copy(19, 10, 7)]

    private static let plans: [Plan] = [
        Plan(.patch0, boosters, [.copy(2, 1, 7)]),
        Plan(.patch0, [amp], [.copy(20, 2, 4), .copy(24, 1)]),
        Plan(.patch0, [switches], [.copy(0, 0)]),
        Plan(.patch0, [soloCom], [.copy(27, 0, 2)]),
        Plan(.patch0, [0x4C], [.copy(48, 1, 2)]),
        Plan(.patch0, [0x50], [.copy(50, 0, 11)]),
        Plan(.patch0, [0x54], [.copy(61, 0, 11)]),
        Plan(.eq2, [0x4E], [.copy(0, 1, 2)]),
        Plan(.eq2, [0x52], [.copy(2, 0, 11)]),
        Plan(.eq2, [0x56], [.copy(13, 0, 11)]),
        Plan(.fx1, [switches], [.copy(0, 1)]),
        Plan(.fx1, [0x1C, 0x1E, 0x20], effectMoves),
        Plan(.fx2, [switches], [.copy(0, 2)]),
        Plan(.fx2, [0x22, 0x24, 0x26], effectMoves),
        Plan(.delay1, [switches], [.copy(0, 3)]),
        Plan(.delay1, [0x28, 0x2A, 0x2C], delayMoves),
        Plan(.delay2, [switches], [.copy(0, 4)]),
        Plan(.delay2, [0x2E, 0x30, 0x32], delayMoves),
        Plan(.patch1, [switches], [.copy(0, 5)]),
        Plan(.patch1, reverbs, [.copy(2, 2), .wide(3, 3), .copy(5, 7, 5), .copy(11, 12)]),
        Plan(.patch1, [0x48], [.copy(16, 1, 2)]),
        Plan(.patch1, [0x4A], [.copy(18, 0, 15)]),
        Plan(.patch1, [0x5A], [.copy(34, 0), .copy(35, 2, 3)]),
        Plan(.patch1, [0x58], [.copy(38, 0, 3)]),
        Plan(.patch1, [0x02], [.copy(49, 2)]),
        Plan(.patch1, [soloCom], [.copy(84, 0, 2)]),
        Plan(.patch1, [0x4E], [.copy(89, 0)]),
        Plan(.patch2, [0x02], [.copy(0, 0), .copy(35, 1)]),
        Plan(.patch2, [0x5A], [.copy(1, 1)]),
        Plan(.patch2, [0x4C], [.copy(2, 0)]),
        Plan(.patch2, [0x48], [.copy(3, 0)]),
        Plan(.patch2, [color], [.copy(25, 0, 5)]),
        Plan(.status, [amp], [.copy(1, 0), .copy(12, 9)]),
        Plan(.solo, [0x3C], [.copy(0, 0, 10)]),
        Plan(.solo, [0x3E], [.copy(10, 0, 2), .wide(12, 2), .copy(14, 6, 8)]),
        Plan(.contour1, [0x42], [.copy(0, 0, 2)]),
        Plan(.contour2, [0x44], [.copy(0, 0, 2)]),
        Plan(.contour3, [0x46], [.copy(0, 0, 2)]),
        Plan(.fsAssign, [0x66], [.copy(0, 0, 2)]),
    ] + (0..<3).map { Plan(.patch2, [reverbs[$0]], [.copy(22 + $0, 1)]) }

    private static let ampTypes = [
        1, 0, 3, 3, 4, 5, 4, 4, 1, 1, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 5, 4, 1, 4, 5, 0, 1, 3, 4, 5,
    ]
    private static let boosterTypes = [0, 1, 2, 3, 4, 5, 6, 13] + Array(7...22) + [-1, -1]
    private static let modFxTypes = [
        0, 1, 2, 3, 4, -1, 5, 6, -1, 7, 8, -1, 9, -1, 10, 11, 12, -1, 13, 14, 15, 16, 17, 18, -1, 19, 20, 21, 22,
        23, -1, 24, -1, -1, -1, 25, 26, 27, 28, 29, 30,
    ]
    private static let delayTypes = [0, 1, 2, -1, -1, -1, 5, 3, 4, 6, 7]
    private static let reverbTypes = [-1, 1, -1, 2, 0, 3, 4]

    private struct Slot {
        let first: Int, regions: [UInt8], types: [Int], fallback: UInt8, switchIndex: Int?, selector: Int?
    }

    private static let slots: [Slot] = [
        Slot(first: 4, regions: boosters, types: boosterTypes, fallback: 0, switchIndex: 0, selector: 0),
        Slot(first: 7, regions: [0x10, 0x12, 0x14], types: modFxTypes, fallback: 23, switchIndex: 1, selector: 1),
        Slot(first: 10, regions: [0x16, 0x18, 0x1A], types: modFxTypes, fallback: 23, switchIndex: 2, selector: 2),
        Slot(first: 13, regions: [0x28, 0x2A, 0x2C], types: delayTypes, fallback: 0, switchIndex: 3, selector: 3),
        Slot(first: 16, regions: reverbs, types: reverbTypes, fallback: 0, switchIndex: 5, selector: 4),
        Slot(first: 19, regions: [0x2E, 0x30, 0x32], types: delayTypes, fallback: 0, switchIndex: nil, selector: nil),
    ]

    private static let flangerLike: [UInt8] = [0, 1, 2, 3, 4, 6, 5, 7]
    private static let assignValues: [Int: [UInt8]] = [
        1: [0, 1, 2, 3, 4, 5, 6, 7, 0], 2: [0, 1, 2, 6, 7, 3, 4, 5], 3: [1, 0, 3, 3, 4, 10, 5, 6, 7, 8, 9],
        4: flangerLike, 5: flangerLike,
        20: [0, 2, 3, 1, 4], 22: [0, 1, 2, 4, 5, 6, 3], 25: [0, 1, 4, 6, 9, 10, 2, 3, 5, 7, 8],
        26: [0, 1, 5, 8, 9, 3, 4, 2, 7, 6],
        27: [0, 1, 2, 5, 3, 4], 33: [0, 2, 1, 3, 4, 5],
    ]
    private static let pedalFunctions: [UInt8] = [0, 1, 3, 4, 5, 7, 6, 8, 9, 2]
    private static let wideRanges: Set<Int> = [1, 2, 25, 26, 31]

    static func convert(_ patch: KatanaLegacyPatch) -> Result? {
        var sound = Sound(image: KatanaGen3Defaults.image())
        for plan in plans {
            guard let source = patch.blocks[plan.block] else { continue }
            for move in plan.moves { sound.apply(move, from: source, to: plan.regions) }
        }
        guard let patch0 = patch.blocks[.patch0], let patch2 = patch.blocks[.patch2], let name = patch.blocks[.name],
              let ampType = patch0[katanaSafe: 17].flatMap({ ampTypes[katanaSafe: Int($0)] }) else { return nil }
        sound.set(amp, 7, UInt8(ampType))
        sound.set(0x00, 0, bytes: name)
        guard convertTypes(patch2, into: &sound) else { return nil }
        if let patch1 = patch.blocks[.patch1], let on = patch1[katanaSafe: 0x56] {
            if on == 0 { sound.set(contour, 0, 0) } else if let select = patch1[katanaSafe: 0x57] { sound.set(contour, 0, select + 1) }
        }
        if let function = patch2[katanaSafe: 30].flatMap({ pedalFunctions[katanaSafe: Int($0)] }) { sound.set(0x5E, 0, function) }
        if let status = patch.blocks[.status] {
            for index in 0..<5 { if let value = status[katanaSafe: 7 + index] { sound.knob[index] = value } }
        }
        convertAssigns(patch, into: &sound)
        let regions = KatanaPatchRegion.all.map { KatanaTone.Region(region: $0.region, bytes: sound.image[$0.region] ?? []) }
        return Result(regions: regions, knob: sound.knob)
    }

    private static func convertTypes(_ patch2: [UInt8], into sound: inout Sound) -> Bool {
        for slot in slots {
            var unsupported = [Bool](repeating: false, count: 3)
            for colour in 0..<3 {
                guard let value = patch2[katanaSafe: slot.first + colour] else { continue }
                guard let mapped = slot.types[katanaSafe: Int(value)] else { return false }
                unsupported[colour] = mapped < 0
                sound.set(slot.regions[colour], 0, mapped < 0 ? slot.fallback : UInt8(mapped))
            }
            if let switchIndex = slot.switchIndex, let selector = slot.selector, let shown = patch2[katanaSafe: 25 + selector],
               unsupported[katanaSafe: Int(shown)] == true {
                sound.set(switches, switchIndex, 0)
            }
            if slot.switchIndex == nil {
                for colour in 0..<3 where unsupported[colour] { sound.set(reverbs[colour], 1, 2) }
            }
        }
        return true
    }

    private static func convertAssigns(_ patch: KatanaLegacyPatch, into sound: inout Sound) {
        for (block, region) in [(KatanaMkIIBlock.knobAssign, UInt8(0x5C)), (.pedalAssign, 0x60)] {
            guard let source = patch.blocks[block] else { continue }
            for index in 0..<34 {
                guard let value = source[katanaSafe: index] else { continue }
                if let table = assignValues[index] {
                    if let renumbered = table[katanaSafe: Int(value)] { sound.set(region, index, renumbered) }
                } else {
                    sound.set(region, index, value)
                }
            }
        }
        guard let ranges = patch.blocks[.pedalRange] else { return }
        var src = 0, dst = 0
        for effect in 0..<34 {
            let width = wideRanges.contains(effect) ? 2 : 1
            let minimum: Move = width == 2 ? .wide(src, dst) : .copy(src, dst)
            let maximum: Move = width == 2 ? .wide(src + 2, dst) : .copy(src + 1, dst)
            sound.apply(minimum, from: ranges, to: [0x62])
            sound.apply(maximum, from: ranges, to: [0x64])
            src += width * 2
            dst += width == 2 ? 4 : 1
        }
    }

    private struct Sound {
        var image: [UInt8: [UInt8]]
        var knob: [UInt8] = [0, 0, 0, 0, 0]

        mutating func set(_ region: UInt8, _ offset: Int, _ value: UInt8) {
            guard image[region] != nil, offset < image[region]!.count else { return }
            image[region]![offset] = value
        }

        mutating func set(_ region: UInt8, _ offset: Int, bytes: [UInt8]) {
            for (step, byte) in bytes.enumerated() { set(region, offset + step, byte) }
        }

        mutating func apply(_ move: Move, from source: [UInt8], to regions: [UInt8]) {
            if move.isWide {
                guard let high = source[katanaSafe: move.src], let low = source[katanaSafe: move.src + 1] else { return }
                let value = Int(high) << 7 | Int(low)
                let nibbles = [value >> 12, value >> 8, value >> 4, value].map { UInt8($0 & 0xF) }
                for region in regions { set(region, move.dst, bytes: nibbles) }
                return
            }
            for step in 0..<move.count {
                guard let byte = source[katanaSafe: move.src + step] else { return }
                for region in regions { set(region, move.dst + step, byte) }
            }
        }
    }
}

fileprivate nonisolated extension Array {
    subscript(katanaSafe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
