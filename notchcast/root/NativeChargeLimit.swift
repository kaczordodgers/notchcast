import Foundation
import SystemConfiguration
import ObjectiveC
import IOKit.ps

enum NativeChargeLimit {
    static func parse(_ output: String) throws -> Int? {
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
        var uid: uid_t = 0
        guard let user = SCDynamicStoreCopyConsoleUser(nil, &uid, nil), uid != 0,
              user as String != "loginwindow" else { throw FanSMC.Failure.refused }
        let ui = limit == nil ? nil : try PowerUI()
        if let ui, !ui.supported { throw FanSMC.Failure.refused }
        let domain = "com.apple.smartcharging.topoffprotection" as CFString
        let host = kCFPreferencesCurrentHost
        func notify() throws {
            guard CFPreferencesSynchronize(domain, user, host) else { throw FanSMC.Failure.refused }
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName("com.apple.smartcharging.defaultschanged" as CFString), nil, nil, true)
        }
        CFPreferencesSetValue("mclLimitValue" as CFString, limit.map { $0 as CFNumber }, domain, user, host)
        CFPreferencesSetValue("MCLFeatureState" as CFString, limit.map { _ in 1 as CFNumber }, domain, user, host)
        try notify()
        if let ui, let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let source = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue(),
           source as String == kIOPMACPowerKey, ui.invoke("isMCLCurrentlyEnabled:") == false {
            guard ui.invoke("enableMCL:") == true else { throw FanSMC.Failure.refused }
            try notify()
        }
    }

    private final class PowerUI {
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

        func invoke(_ name: String) -> Bool? {
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
