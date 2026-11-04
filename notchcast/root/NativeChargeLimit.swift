import Foundation
import ObjectiveC
import IOKit.ps
import Synchronization

enum NativeChargeLimit {
    enum Failure: Error, LocalizedError {
        case unconfirmed
        var errorDescription: String? { "Charge limit state is unconfirmed after timeout" }
    }
    static func parse(_ output: String) throws -> Int? {
        if output == "No battery level limits set\n" { return nil }
        guard output.hasPrefix("Battery level limits:"), let start = output.firstIndex(of: "(") else {
            throw FanSMC.Failure.invalidValue
        }
        let list = String(output[start...])
        guard let data = list.data(using: .utf8),
              let entries = try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [[String: Any]] else { throw FanSMC.Failure.invalidValue }
        var limits = Set<Int>()
        for entry in entries where entry["chargeSocLimitReason"] as? String == "manualChargeLimit" {
            guard let rawValue = entry["chargeSocLimitSoc"] as? String,
                  let value = Int(rawValue), (1...100).contains(value),
                  let rawTerminated = entry["Terminated"] as? String,
                  let terminated = Int(rawTerminated), (0...1).contains(terminated) else {
                throw FanSMC.Failure.invalidValue
            }
            if terminated == 0 { limits.insert(value) }
        }
        guard limits.count <= 1 else { throw FanSMC.Failure.invalidValue }
        return limits.first
    }

    static func read() throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "battlimit"]
        process.environment = [:]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        finished.wait()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw FanSMC.Failure.refused
        }
        return try parse(String(decoding: data, as: UTF8.self)).map { "\($0)\n" } ?? "off\n"
    }

    static func run(_ command: RootContract.Command) throws {
        guard geteuid() == 0 else { throw FanSMC.Failure.refused }
        let limit: Int?
        switch command {
        case .chargeLimit60: limit = 60
        case .chargeLimit70: limit = 70
        case .chargeLimit80: limit = 80
        case .chargeLimit90: limit = 90
        case .chargeLimitOff: limit = nil
        default: throw FanSMC.Failure.invalidValue
        }
        guard setenv("HOME", "/var/root", 1) == 0, unsetenv("CFFIXED_USER_HOME") == 0 else {
            throw FanSMC.Failure.refused
        }
        let deadline = DispatchTime.now() + .seconds(7)
        let restoreDeadline = deadline + .seconds(2)
        let ui = limit == nil ? nil : try PowerUI()
        if let ui {
            guard try bounded(deadline: deadline, { ui.supported }) == true else {
                throw FanSMC.Failure.refused
            }
        }
        let domain = "com.apple.smartcharging.topoffprotection" as CFString
        let user = kCFPreferencesCurrentUser
        let host = kCFPreferencesCurrentHost
        let keys = ["mclLimitValue", "MCLFeatureState"] as [CFString]
        let prior = keys.map { CFPreferencesCopyValue($0, domain, user, host) }
        func notify() {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.apple.smartcharging.defaultschanged" as CFString), nil, nil, true)
        }
        func synchronize(until deadline: DispatchTime) throws {
            guard try bounded(deadline: deadline, {
                CFPreferencesSynchronize("com.apple.smartcharging.topoffprotection" as CFString,
                    kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            }) == true else { throw FanSMC.Failure.refused }
        }
        try apply(write: {
            CFPreferencesSetValue(keys[0], limit.map { $0 as CFNumber }, domain, user, host)
            CFPreferencesSetValue(keys[1], limit.map { _ in 1 as CFNumber }, domain, user, host)
            try synchronize(until: deadline)
            notify()
            for (key, expected) in zip(keys, [limit, limit.map { _ in 1 }]) {
                let actual = CFPreferencesCopyValue(key, domain, user, host)
                if let expected {
                    guard let number = actual as? NSNumber, number == NSNumber(value: expected) else {
                        throw FanSMC.Failure.refused
                    }
                } else if actual != nil { throw FanSMC.Failure.refused }
            }
        }, enable: {
            if let ui {
                guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                      let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
                    throw FanSMC.Failure.refused
                }
                if source as String == kIOPMACPowerKey {
                    guard let enabled = try ui.invoke("isMCLCurrentlyEnabled:", deadline: deadline) else {
                        throw FanSMC.Failure.refused
                    }
                    if !enabled {
                        guard try ui.invoke("enableMCL:", deadline: deadline) == true else {
                            throw FanSMC.Failure.refused
                        }
                        notify()
                    }
                }
            }
        }, restore: {
            for (key, value) in zip(keys, prior) {
                CFPreferencesSetValue(key, value, domain, user, host)
            }
            try synchronize(until: restoreDeadline)
            notify()
        })
    }

    static func apply(write: () throws -> Void, enable: () throws -> Void,
                      restore: () throws -> Void) throws {
        do {
            try write()
            try enable()
        } catch Failure.unconfirmed {
            throw Failure.unconfirmed
        } catch {
            try restore()
            throw error
        }
    }

    static func bounded(timeout: DispatchTimeInterval = .seconds(4),
                        _ operation: @escaping @Sendable () -> Bool?) throws -> Bool? {
        try bounded(deadline: .now() + timeout, operation)
    }

    static func bounded(deadline: DispatchTime,
                        _ operation: @escaping @Sendable () -> Bool?) throws -> Bool? {
        guard DispatchTime.now() < deadline else { throw Failure.unconfirmed }
        let result = Mutex<Bool?>(nil)
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let value = operation()
            result.withLock { $0 = value }
            finished.signal()
        }
        guard finished.wait(timeout: deadline) == .success else { throw Failure.unconfirmed }
        return result.withLock { $0 }
    }

    private final class PowerUI: @unchecked Sendable {
        private let client: AnyObject

        init() throws {
            guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW | RTLD_GLOBAL) != nil,
                  let type = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type,
                  let allocated = type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
                  let initialized = allocated.perform(NSSelectorFromString("initWithClientName:"),
                    with: "Notchcast" as NSString)?.takeUnretainedValue() else { throw FanSMC.Failure.refused }
            client = initialized
        }

        var supported: Bool {
            let selector = NSSelectorFromString("isMCLSupported")
            guard let method = class_getInstanceMethod(type(of: client), selector) else { return false }
            typealias Query = @convention(c) (AnyObject, Selector) -> ObjCBool
            return unsafeBitCast(method_getImplementation(method), to: Query.self)(client, selector).boolValue
        }

        func invoke(_ name: String, deadline: DispatchTime) throws -> Bool? {
            try NativeChargeLimit.bounded(deadline: deadline) { self.invokeSynchronously(name) }
        }

        private func invokeSynchronously(_ name: String) -> Bool? {
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(type(of: client), selector) else { return nil }
            typealias Query = @convention(c)
                (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> ObjCBool
            var error: NSError?
            let result = unsafeBitCast(method_getImplementation(method), to: Query.self)(client, selector, &error)
            return error == nil ? result.boolValue : nil
        }
    }
}
