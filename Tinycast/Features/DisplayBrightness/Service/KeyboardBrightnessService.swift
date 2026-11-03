import Darwin
import Foundation
import ObjectiveC

// The client and its Objective-C method calls are confined to the lock.
final class KeyboardBrightnessService: @unchecked Sendable {
    private typealias CopyIDs = @convention(c) (NSObject, Selector) -> Unmanaged<AnyObject>?
    private typealias BuiltIn = @convention(c) (NSObject, Selector, UInt64) -> ObjCBool
    private typealias Get = @convention(c) (NSObject, Selector, UInt64) -> Float
    private typealias Set = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

    private struct Client {
        let object: NSObject
        let id: UInt64
        let get: Get
        let set: Set
    }

    private static let clientType: NSObject.Type? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY),
            dlsym(handle, "OBJC_CLASS_$_KeyboardBrightnessClient") != nil else { return nil }
        return NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
    }()

    private let lock = NSLock()
    private var client: Client?
    private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

    @concurrent func level() async -> BrightnessLevel? {
        lock.withLock { read() }
    }

    @concurrent func set(_ value: Double) async -> BrightnessLevel? {
        lock.withLock { write(value) }
    }

    @concurrent func step(up: Bool, fine: Bool) async -> BrightnessLevel? {
        lock.withLock {
            guard let current = read() else { return nil }
            return write(max(0, current.stepped(up: up, fine: fine).value))
        }
    }

    private func read() -> BrightnessLevel? {
        guard !Task.isCancelled, let client = resolve() else { return nil }
        let value = client.get(client.object, getSelector, client.id)
        guard value.isFinite, (0...1).contains(value) else { return nil }
        return BrightnessLevel(Double(value))
    }

    private func write(_ value: Double) -> BrightnessLevel? {
        guard !Task.isCancelled, value.isFinite, let client = resolve() else { return nil }
        let bounded = min(max(value, 0), 1)
        guard client.set(client.object, setSelector, Float(bounded), client.id).boolValue
        else { return nil }
        return read()
    }

    private func resolve() -> Client? {
        if let client { return client }
        guard let type = Self.clientType else { return nil }
        let object = type.init()
        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
        guard let copy = implementation(object, idsSelector), let builtIn = implementation(object, builtInSelector),
              let get = implementation(object, getSelector), let set = implementation(object, setSelector) else { return nil }
        let copyIDs = unsafeBitCast(copy, to: CopyIDs.self)
        let isBuiltIn = unsafeBitCast(builtIn, to: BuiltIn.self)
        guard let ids = copyIDs(object, idsSelector)?.takeRetainedValue() as? [NSNumber],
              let id = ids.map(\.uint64Value).first(where: { isBuiltIn(object, builtInSelector, $0).boolValue })
        else { return nil }
        let resolved = Client(object: object, id: id,
                              get: unsafeBitCast(get, to: Get.self), set: unsafeBitCast(set, to: Set.self))
        client = resolved
        return resolved
    }

    private func implementation(_ object: NSObject, _ selector: Selector) -> IMP? {
        guard object.responds(to: selector) else { return nil }
        return object.method(for: selector)
    }
}
