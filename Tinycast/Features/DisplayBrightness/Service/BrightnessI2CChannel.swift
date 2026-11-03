import CoreGraphics
import Darwin
import Foundation
import IOKit

final class BrightnessI2CChannel {
    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias Transfer = @convention(c)
        (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private struct Calls: Sendable {
        let create: Create
        let write: Transfer
        let read: Transfer
    }

    private static let calls: Calls? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let create = dlsym(handle, "IOAVServiceCreateWithService"),
              let write = dlsym(handle, "IOAVServiceWriteI2C"),
              let read = dlsym(handle, "IOAVServiceReadI2C") else { return nil }
        return Calls(create: unsafeBitCast(create, to: Create.self),
                     write: unsafeBitCast(write, to: Transfer.self), read: unsafeBitCast(read, to: Transfer.self))
    }()

    private let service: CFTypeRef
    private var maximum: UInt16?
    private var lastCommand: ContinuousClock.Instant?

    private init(service: CFTypeRef) { self.service = service }

    func read() -> Double? {
        guard let calls = Self.calls else { return nil }
        for _ in 0..<3 {
            guard !Task.isCancelled else { return nil }
            pace()
            var request = BrightnessDDC.request()
            guard request.withUnsafeMutableBytes({ buffer in
                calls.write(service, BrightnessDDC.chip, BrightnessDDC.host,
                            buffer.baseAddress!, UInt32(buffer.count))
            }) == kIOReturnSuccess else {
                lastCommand = .now
                continue
            }
            Thread.sleep(forTimeInterval: 0.05)
            var reply = [UInt8](repeating: 0, count: BrightnessDDC.replyLength)
            let result = reply.withUnsafeMutableBytes { buffer in
                calls.read(service, BrightnessDDC.chip, BrightnessDDC.host,
                           buffer.baseAddress!, UInt32(buffer.count))
            }
            lastCommand = .now
            if result == kIOReturnSuccess, let reading = BrightnessDDC.parse(reply) {
                maximum = reading.maximum
                return Double(reading.current) / Double(reading.maximum)
            }
        }
        return nil
    }

    func write(_ level: Double) -> Bool {
        guard let calls = Self.calls, let maximum, !Task.isCancelled else { return false }
        pace()
        guard !Task.isCancelled else { return false }
        var packet = BrightnessDDC.write(BrightnessDDC.deviceValue(level, maximum: maximum))
        defer { lastCommand = .now }
        return packet.withUnsafeMutableBytes { buffer in
            calls.write(service, BrightnessDDC.chip, BrightnessDDC.host,
                        buffer.baseAddress!, UInt32(buffer.count)) == kIOReturnSuccess
        }
    }

    private func pace() {
        guard let lastCommand else { return }
        let remaining = lastCommand.duration(to: .now)
        if remaining < .milliseconds(50) {
            let seconds = Double(remaining.components.seconds)
                + Double(remaining.components.attoseconds) / 1e18
            Thread.sleep(forTimeInterval: max(0, 0.05 - seconds))
        }
    }

    static func discover() -> [String: BrightnessI2CChannel] {
        guard let calls else { return [:] }
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
                                      IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS
        else { return [:] }
        defer { IOObjectRelease(iterator) }
        var channels: [String: BrightnessI2CChannel] = [:]
        var uuid: String?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var name = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &name)
            let end = name.firstIndex(of: 0) ?? name.endIndex
            let label = String(bytes: name[..<end].map { UInt8(bitPattern: $0) }, encoding: .utf8)
            if label == "AppleCLCD2" || label == "IOMobileFramebufferShim" {
                uuid = property(entry, "EDID UUID")
            } else if label == "DCPAVServiceProxy" {
                if let uuid, property(entry, "Location") == "External",
                   let service = calls.create(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                    channels[uuid.uppercased()] = BrightnessI2CChannel(service: service)
                }
                uuid = nil
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return channels
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }
}
