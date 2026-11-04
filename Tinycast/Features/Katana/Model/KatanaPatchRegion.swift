import Foundation

nonisolated struct KatanaPatchRegion: Equatable, Sendable {
    var region: UInt8
    var length: Int
    var block: String

    static let all: [KatanaPatchRegion] = [
        KatanaPatchRegion(region: 0x00, length: 16, block: "COM"),
        KatanaPatchRegion(region: 0x02, length: 3, block: "OTHER"),
        KatanaPatchRegion(region: 0x04, length: 5, block: "COLOR"),
        KatanaPatchRegion(region: 0x06, length: 10, block: "AMP"),
        KatanaPatchRegion(region: 0x08, length: 6, block: "SW"),
        KatanaPatchRegion(region: 0x0A, length: 8, block: "BOOSTER(1)"),
        KatanaPatchRegion(region: 0x0C, length: 8, block: "BOOSTER(2)"),
        KatanaPatchRegion(region: 0x0E, length: 8, block: "BOOSTER(3)"),
        KatanaPatchRegion(region: 0x10, length: 1, block: "FX(1)"),
        KatanaPatchRegion(region: 0x12, length: 1, block: "FX(2)"),
        KatanaPatchRegion(region: 0x14, length: 1, block: "FX(3)"),
        KatanaPatchRegion(region: 0x16, length: 1, block: "FX(4)"),
        KatanaPatchRegion(region: 0x18, length: 1, block: "FX(5)"),
        KatanaPatchRegion(region: 0x1A, length: 1, block: "FX(6)"),
        KatanaPatchRegion(region: 0x1C, length: 225, block: "FX_DETAIL(1)"),
        KatanaPatchRegion(region: 0x1E, length: 225, block: "FX_DETAIL(2)"),
        KatanaPatchRegion(region: 0x20, length: 225, block: "FX_DETAIL(3)"),
        KatanaPatchRegion(region: 0x22, length: 225, block: "FX_DETAIL(4)"),
        KatanaPatchRegion(region: 0x24, length: 225, block: "FX_DETAIL(5)"),
        KatanaPatchRegion(region: 0x26, length: 225, block: "FX_DETAIL(6)"),
        KatanaPatchRegion(region: 0x28, length: 17, block: "DELAY(1)"),
        KatanaPatchRegion(region: 0x2A, length: 17, block: "DELAY(2)"),
        KatanaPatchRegion(region: 0x2C, length: 17, block: "DELAY(3)"),
        KatanaPatchRegion(region: 0x2E, length: 17, block: "DELAY(4)"),
        KatanaPatchRegion(region: 0x30, length: 17, block: "DELAY(5)"),
        KatanaPatchRegion(region: 0x32, length: 17, block: "DELAY(6)"),
        KatanaPatchRegion(region: 0x34, length: 13, block: "REVERB(1)"),
        KatanaPatchRegion(region: 0x36, length: 13, block: "REVERB(2)"),
        KatanaPatchRegion(region: 0x38, length: 13, block: "REVERB(3)"),
        KatanaPatchRegion(region: 0x3A, length: 2, block: "SOLO_COM"),
        KatanaPatchRegion(region: 0x3C, length: 10, block: "SOLO_EQ"),
        KatanaPatchRegion(region: 0x3E, length: 14, block: "SOLO_DELAY"),
        KatanaPatchRegion(region: 0x40, length: 1, block: "CONTOUR_COM"),
        KatanaPatchRegion(region: 0x42, length: 2, block: "CONTOUR(1)"),
        KatanaPatchRegion(region: 0x44, length: 2, block: "CONTOUR(2)"),
        KatanaPatchRegion(region: 0x46, length: 2, block: "CONTOUR(3)"),
        KatanaPatchRegion(region: 0x48, length: 3, block: "PEDALFX_COM"),
        KatanaPatchRegion(region: 0x4A, length: 15, block: "PEDALFX"),
        KatanaPatchRegion(region: 0x4C, length: 3, block: "EQ_EACH(1)"),
        KatanaPatchRegion(region: 0x4E, length: 3, block: "EQ_EACH(2)"),
        KatanaPatchRegion(region: 0x50, length: 11, block: "EQ_PEQ(1)"),
        KatanaPatchRegion(region: 0x52, length: 11, block: "EQ_PEQ(2)"),
        KatanaPatchRegion(region: 0x54, length: 11, block: "EQ_GE10(1)"),
        KatanaPatchRegion(region: 0x56, length: 11, block: "EQ_GE10(2)"),
        KatanaPatchRegion(region: 0x58, length: 3, block: "NS"),
        KatanaPatchRegion(region: 0x5A, length: 5, block: "SENDRETURN"),
        KatanaPatchRegion(region: 0x5C, length: 34, block: "ASSIGN_KNOBS"),
        KatanaPatchRegion(region: 0x5E, length: 1, block: "ASSIGN_EXPPDL_FUNC"),
        KatanaPatchRegion(region: 0x60, length: 34, block: "ASSIGN_EXPPDL_DETAIL"),
        KatanaPatchRegion(region: 0x62, length: 49, block: "ASSIGN_EXPPDL_MIN"),
        KatanaPatchRegion(region: 0x64, length: 49, block: "ASSIGN_EXPPDL_MAX"),
        KatanaPatchRegion(region: 0x66, length: 2, block: "ASSIGN_FS"),
    ]

    static let essential: Set<UInt8> = [0x00, 0x06, 0x08]

    static func named(_ block: String) -> KatanaPatchRegion? { all.first { $0.block == block } }
}
