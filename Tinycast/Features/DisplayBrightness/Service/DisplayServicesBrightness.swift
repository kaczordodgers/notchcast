import CoreGraphics
import Darwin

enum DisplayServicesBrightness {
    private typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (UInt32, Float) -> Int32

    private struct Calls: Sendable {
        let get: Get
        let set: Set
    }

    private static let calls: Calls? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
            let get = dlsym(handle, "DisplayServicesGetBrightness"),
            let set = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return Calls(get: unsafeBitCast(get, to: Get.self), set: unsafeBitCast(set, to: Set.self))
    }()

    static func read(_ display: UInt32) -> Double? {
        var value: Float = 0
        guard let calls, calls.get(display, &value) == 0,
              value.isFinite, (0...1).contains(value) else { return nil }
        return Double(value)
    }

    static func write(_ value: Double, to display: UInt32) -> Bool {
        calls?.set(display, Float(value)) == 0
    }
}
