// notchcast-sources: Tinycast/Features/Katana/Model/*.swift
import Foundation

@main
struct Mk1GainTest {
    static func main() throws {
        var params: [String: Any] = [:]
        for index in 1...16 { params["patch_name\(index)"] = 65 }
        for gain in [0, 17, 83, 100] {
            params["preamp_a_gain"] = gain
            let patch = KatanaLegacyFormats.mk1(params: params, comment: "")!
            let converted = KatanaLegacyConverter.convert(patch)!
            precondition(converted.regions.first { $0.region == 0x06 }!.bytes[0] == UInt8(gain),
                         "Mk1 gain must survive import instead of becoming factory gain 50")
        }
        print("PASS: Mk1 gain survives conversion")
    }
}
