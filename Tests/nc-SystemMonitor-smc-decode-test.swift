// notchcast-sources: -parse-as-library Tinycast/Features/SystemMonitor/Model/SMCValue.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/SMCSensorReading.swift
// notchcast-kit: root
// notchcast-sources: notchcast/root/FanSMC.swift
import Foundation

@main
struct SMCDecodeTest {
    static func info(_ type: String, _ size: Int) -> SMCValue.KeyInfo {
        SMCValue.KeyInfo(size: size, type: type, attributes: 0)
    }

    static func app(_ type: String, _ bytes: [UInt8]) -> Double? {
        SMCValue(info: info(type, bytes.count), bytes: bytes).number
    }

    static func helper(_ type: String, _ bytes: [UInt8], size: Int? = nil) -> Double? {
        try? FanSMC.decode(bytes, info: FanSMC.Info(size: size ?? bytes.count, type: type))
    }

    static func main() {
        let shared: [(String, [UInt8], Double)] = [
            ("flt ", [0, 0, 0x7a, 0x45], 4_000), ("flt ", [0, 0, 0x48, 0x42], 50),
            ("fpe2", [0x3e, 0x81], 4_000.25), ("fpe2", [0x1f, 0x42], 2_000.5),
            ("ui8 ", [2], 2), ("ui8 ", [0], 0), ("ui16", [4, 0xd2], 1_234),
            ("ui32", [0x12, 0x34, 0x56, 0x78], 0x12345678),
        ]
        for (type, bytes, value) in shared {
            precondition(app(type, bytes) == value, "app decodes \(type) \(bytes)")
            precondition(helper(type, bytes) == value, "helper decodes \(type) \(bytes) the same")
        }
        let appOnly: [(String, [UInt8], Double)] = [
            ("sp78", [0x32, 0x80], 50.5), ("sp78", [0xf5, 0x80], -10.5),
            ("si8 ", [0xfe], -2), ("si16", [0xff, 0xfe], -2), ("flt ", [0, 0, 0x20, 0xc1], -10),
        ]
        for (type, bytes, value) in appOnly {
            precondition(app(type, bytes) == value, "app decodes signed \(type)")
            precondition(helper(type, bytes) == nil, "helper still refuses \(type) \(bytes)")
        }
        for bytes: [UInt8] in [[0, 0, 0x80, 0x7f], [0, 0, 0xc0, 0x7f]] {
            precondition(app("flt ", bytes) == nil && helper("flt ", bytes) == nil, "non-finite refused")
        }
        precondition(helper("flt ", [0, 0, 0x7a, 0x45], size: 2) == nil, "size mismatch refused")
        precondition(helper("ui8 ", [1, 0], size: 1) == nil, "extra byte refused")
        precondition(helper("nope", [1]) == nil && app("nope", [1]) == nil, "unknown type refused")

        precondition(SMCSensorReading.fanRPM(app("flt ", [0, 0, 0x7a, 0x45])) == 4_000, "fan RPM")
        precondition(SMCSensorReading.fanRPM(app("flt ", [0, 0x30, 0xf2, 0x46])) == nil, "fan RPM above 30k")
        precondition(SMCSensorReading.powerWatts(app("flt ", [0, 0, 0x48, 0x42])) == 50, "system power")
        print("PASS: SMC fixtures decode the same in the app and the helper")
    }
}
