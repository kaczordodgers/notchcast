import Foundation

@MainActor final class MiddleClickTouchSource {
    typealias Device = UnsafeMutableRawPointer
    typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

    private let createList: @convention(c) () -> Unmanaged<CFArray>?
    private let register: @convention(c) (Device, Callback) -> Void
    private let unregister: @convention(c) (Device, Callback) -> Void
    private let startDevice: @convention(c) (Device, Int32) -> Void
    private let stopDevice: @convention(c) (Device) -> Void

    private nonisolated static let stride = 96
    private nonisolated static let identifierOffset = 16
    private nonisolated static let stateOffset = 20
    private nonisolated static let xOffset = 32
    private nonisolated static let yOffset = 36
    private nonisolated static let contactStates: ClosedRange<Int32> = 3...4

    private static let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    private let handle: UnsafeMutableRawPointer

    init?() {
        guard let handle = dlopen(Self.path, RTLD_LAZY) else { return nil }
        guard let list = dlsym(handle, "MTDeviceCreateList"), let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"), let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop") else { dlclose(handle); return nil }
        self.handle = handle
        createList = unsafeBitCast(list, to: (@convention(c) () -> Unmanaged<CFArray>?).self)
        self.register = unsafeBitCast(register, to: (@convention(c) (Device, Callback) -> Void).self)
        self.unregister = unsafeBitCast(unregister, to: (@convention(c) (Device, Callback) -> Void).self)
        startDevice = unsafeBitCast(start, to: (@convention(c) (Device, Int32) -> Void).self)
        stopDevice = unsafeBitCast(stop, to: (@convention(c) (Device) -> Void).self)
    }

    private nonisolated(unsafe) static var sink: (@Sendable (Int, [TouchPoint], TimeInterval) -> Void)?
    // The C callback has no context argument; sinkLock owns every access to its single sink.
    private nonisolated static let sinkLock = NSLock()

    nonisolated static let maxTouches = 16

    nonisolated static func isSane(_ points: [TouchPoint]) -> Bool {
        points.count <= maxTouches && points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }
    }

    private nonisolated static let callback: Callback = { device, touches, count, timestamp, _ in
        guard let device, count == 0 || touches != nil, (0...Int32(MiddleClickTouchSource.maxTouches)).contains(count),
              let sink = MiddleClickTouchSource.sinkLock.withLock({ MiddleClickTouchSource.sink }) else { return 0 }
        let points = (0..<Int(count)).map { index -> TouchPoint in
            let record = UnsafeRawPointer(touches!) + index * MiddleClickTouchSource.stride
            let state = record.load(fromByteOffset: MiddleClickTouchSource.stateOffset, as: Int32.self)
            return TouchPoint(id: record.load(fromByteOffset: MiddleClickTouchSource.identifierOffset, as: Int32.self),
                              x: record.load(fromByteOffset: MiddleClickTouchSource.xOffset, as: Float.self),
                              y: record.load(fromByteOffset: MiddleClickTouchSource.yOffset, as: Float.self),
                              down: MiddleClickTouchSource.contactStates.contains(state))
        }
        guard MiddleClickTouchSource.isSane(points) else { return 0 }
        sink(Int(bitPattern: device), points, timestamp)
        return 0
    }

    private var devices: CFArray?

    isolated deinit { stop(); dlclose(handle) }

    func start(_ sink: @escaping @Sendable (Int, [TouchPoint], TimeInterval) -> Void) -> Bool {
        stop()
        guard let list = createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else { return false }
        Self.sinkLock.withLock { Self.sink = sink }
        devices = list
        for index in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            let pointer = UnsafeMutableRawPointer(mutating: device)
            register(pointer, Self.callback)
            startDevice(pointer, 0)
        }
        return true
    }

    func stop() {
        guard let list = devices else { return }
        devices = nil
        for index in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            let pointer = UnsafeMutableRawPointer(mutating: device)
            stopDevice(pointer)
            unregister(pointer, Self.callback)
        }
        Self.sinkLock.withLock { Self.sink = nil }
    }
}
