// notchcast-sources: Tinycast/Features/DisplayBrightness/Model/*.swift
// notchcast-sources: Tinycast/Features/DisplayBrightness/Service/*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/NSScreen+DisplayID.swift
import Foundation

@main
struct DisplayBrightnessModelTest {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        func close(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.0000001 }

        check(BrightnessLevel(.nan).value == 0, "NaN must not reach hardware")
        check(BrightnessLevel(.infinity).value == 1, "Upper clamp")
        check(BrightnessLevel(-.infinity).value == -0.25, "Lower clamp")
        check(BrightnessLevel(-1, softwareOnly: true).value == 0, "Software lower clamp")
        check(BrightnessLevel(2, softwareOnly: true).value == 1, "Software upper clamp")
        check(BrightnessLevel(-0.25).hardware == 0, "Extra dimming keeps the hardware at minimum")
        check(close(BrightnessLevel(-0.25).picture, 0.05), "Dimming floor")
        check(close(BrightnessLevel(-0.125).picture, 0.525), "Extra dimming midpoint")
        check(BrightnessLevel(0).picture == 1, "Zero restores the display profile")
        check(BrightnessLevel(1).picture == 1, "Hardware light needs no gamma")
        let changed = BrightnessLevel(0.25).refreshed(hardware: 0.75)
        check(changed.stepped(up: true, fine: false).value == 0.8125,
              "Step from the fresh system reading")
        check(changed.stepped(up: false, fine: false).value == 0.6875,
              "Step down from the fresh system reading")
        let dimmed = BrightnessLevel(-0.125)
        check(dimmed.refreshed(hardware: 0) == dimmed, "Minimum hardware preserves extra dimming")
        let raised = dimmed.refreshed(hardware: 0.5)
        check(raised.value == 0.5 && !raised.isDimmed, "External backlight increase drops extra dimming")
        check(raised.stepped(up: false, fine: false).value == 0.4375,
              "External backlight increase becomes the next step baseline")
        check(BrightnessLevel(0.5).refreshed(hardware: 0).value == 0,
              "External decrease to minimum replaces the cached hardware level")
        check(close(BrightnessLevel(0.5, softwareOnly: true).picture, 0.525), "Software midpoint")
        check(BrightnessLevel(1, softwareOnly: true).picture == 1, "Software maximum")
        for fine in [false, true] {
            let count = fine ? 64 : 16
            var level = BrightnessLevel(0)
            for _ in 0..<count { level = level.stepped(up: true, fine: fine) }
            check(level.value == 1, "Sixteen hardware steps or sixty-four fine steps")
            check(level.stepped(up: true, fine: fine).value == 1, "Upper step clamp")
            for _ in 0..<(count + count / 4) { level = level.stepped(up: false, fine: fine) }
            check(level.value == -0.25, "Four extra dimming steps")
            check(level.stepped(up: false, fine: fine).value == -0.25, "Lower step clamp")
        }
        check(close(BrightnessLevel(0.1).stepped(up: true, fine: false).value, 0.125), "Up snaps forward")
        check(close(BrightnessLevel(0.1).stepped(up: false, fine: false).value, 0.0625), "Down snaps backward")
        check(BrightnessLevel(0, softwareOnly: true).stepped(up: false, fine: false).value == 0,
              "Software steps never extend below zero")
        let first = BrightnessDisplay.ID(rawValue: 1, uuid: "aabb")
        check(first == .init(rawValue: 1, uuid: "AABB"), "Canonical UUID")
        check(first != .init(rawValue: 1, uuid: "ccdd"), "Reused display IDs cannot address a different display")
        check(first != .init(rawValue: 2, uuid: "aabb"), "A new connection is a new destination")
        check(BrightnessDDC.request() == [0x82, 0x01, 0x10, 0xAC], "DDC request bytes")
        check(BrightnessDDC.write(50) == [0x84, 0x03, 0x10, 0, 50, 0x9A], "DDC write bytes")
        check(BrightnessDDC.deviceValue(0.5, maximum: 255) == 128, "Native maximum and rounding")
        check(BrightnessDDC.deviceValue(.nan, maximum: 100) == 0, "Invalid native conversion")
        check(BrightnessDDC.deviceValue(2, maximum: 100) == 100, "Native clamp")
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0, 0x10, 0, 1, 0, 0, 128]
        reply.append(reply.reduce(UInt8(0x50), ^))
        check(BrightnessDDC.parse(reply)?.maximum == 256, "Big-endian maximum")
        check(BrightnessDDC.parse(reply)?.current == 128, "Big-endian current")
        for index in reply.indices {
            var damaged = reply
            damaged[index] ^= 1
            check(BrightnessDDC.parse(damaged) == nil, "Reject damaged replies")
        }
        for index in [0, 1, 2, 3, 4, 6, 8] {
            var invalid = reply
            invalid[index] = index == 8 ? 2 : index == 6 ? 0 : 0xFF
            invalid[10] = invalid.prefix(10).reduce(UInt8(0x50), ^)
            check(BrightnessDDC.parse(invalid) == nil, "Reject checksummed malformed replies")
        }
        check(BrightnessDDC.parse(Array(reply.dropLast())) == nil, "Truncated reply")
        check(BrightnessDDC.parse(reply + [0]) == nil, "Overlong reply")
        print("PASS: \(checks) display brightness model checks; no hardware accessed")
    }
}
