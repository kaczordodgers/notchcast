// notchcast-sources: -parse-as-library Tinycast/Features/Notchcast/Root/*.swift Tinycast/Platform/ProcessExit.swift
import Darwin
import Foundation

#if FAN_SMC_TEST
@main
struct FanSMCTest {
    final class Fixture: FanSMC.Access {
        var values: [String: Double] = [
            "FNum": 2, "Ftst": 0,
            "F0Mn": 1_000, "F0Mx": 6_000, "F0Ac": 1_200, "F0Tg": 1_000, "F0Md": 0,
            "F1Mn": 2_000, "F1Mx": 7_000, "F1Ac": 2_200, "F1Tg": 2_000, "F1Md": 0,
        ]
        var writes: [String] = []
        var failures: Set<String> = []
        var infoFailures: Set<String> = []
        var readFailures: Set<String> = []
        var missing: Set<String> = []
        var rejectedModes: [String: Int] = [:]
        var instant = ContinuousClock.now
        var elapsed = Duration.zero
        var pauses: [Duration] = []

        func info(_ key: String) throws -> FanSMC.Info? {
            if infoFailures.contains(key) { throw FanSMC.Failure.refused }
            guard !missing.contains(key), values[key] != nil else { return nil }
            return FanSMC.Info(size: key == "FNum" || key == "Ftst" || key.hasSuffix("Md")
                || key.hasSuffix("md") ? 1 : 4, type: key == "FNum" || key == "Ftst"
                || key.hasSuffix("Md") || key.hasSuffix("md") ? "ui8 " : "flt ")
        }

        func read(_ key: String, info: FanSMC.Info) throws -> [UInt8] {
            if readFailures.contains(key) { throw FanSMC.Failure.refused }
            return try FanSMC.encode(values[key]!, info: info)
        }

        func write(_ key: String, bytes: [UInt8]) throws {
            let value = try FanSMC.decode(bytes, info: info(key)!)
            writes.append("\(key)=\(Int(value))")
            if failures.contains(key) { throw FanSMC.Failure.refused }
            if value == 1, let remaining = rejectedModes[key], remaining > 0 {
                rejectedModes[key] = remaining - 1
            } else {
                values[key] = value
            }
        }

        var controller: FanSMC.Controller {
            FanSMC.Controller(smc: self, now: { self.instant }, pause: {
                self.pauses.append($0)
                self.elapsed += $0
                self.instant = self.instant.advanced(by: $0)
            })
        }
    }

    static func main() throws {
        try validateValues()
        try validateSequence()
        try validateRecovery()
        try validateBattery()
        try validateChargeLimit()
        try validateTools()
        print("PASS: fan targets, codecs, write order, shared 5s retry window and Auto recovery (fake SMC only)")
    }

    private static func rejects(_ operation: () throws -> Void) {
        do {
            try operation()
            preconditionFailure("Expected failure")
        } catch {}
    }

    private static func validateTools() throws {
        precondition(Power.arguments(.standbyOff) == ["-a", "standby", "0"])
        precondition(Power.arguments(.standbyOn) == ["-a", "standby", "1"])
        precondition(Power.arguments(.autopoweroffOff) == ["-a", "autopoweroff", "0"])
        precondition(Power.arguments(.autopoweroffOn) == ["-a", "autopoweroff", "1"])
        precondition(Power.arguments(.ping) == nil)
        precondition(Spotlight.arguments(.spotlightOff) == ["-a", "-i", "off"])
        precondition(Spotlight.arguments(.spotlightOn) == ["-a", "-i", "on"])
        precondition(Spotlight.arguments(.ping) == nil)
        let sudo = "auth include sudo_local\n"
        let rule = "auth       sufficient     pam_tid.so\n"
        for original in ["", "# preserved\n", "auth required pam_other.so"] {
            let enabled = try TouchIDPolicy.replacement(sudo: sudo, local: original, enabled: true)
            let expected = original + (original.isEmpty || original.hasSuffix("\n") ? "" : "\n") + rule
            precondition(enabled == expected)
            let repeated = try TouchIDPolicy.replacement(sudo: sudo, local: enabled, enabled: true)
            precondition(repeated == nil)
            let disabled = try TouchIDPolicy.replacement(sudo: sudo, local: enabled, enabled: false)
            precondition(disabled == expected.replacingOccurrences(of: rule, with: ""))
        }
        let absent = try TouchIDPolicy.replacement(sudo: sudo, local: nil, enabled: true)
        precondition(absent == rule)
        for original: String? in [nil, "", "# preserved\n", "auth required pam_other.so\n"] {
            let unchanged = try TouchIDPolicy.replacement(sudo: sudo, local: original, enabled: false)
            precondition(unchanged == nil)
        }
        let removed = try TouchIDPolicy.replacement(
            sudo: sudo, local: "# keep\nauth sufficient pam_tid.so # active\nauth required pam_other.so\n",
            enabled: false)
        precondition(removed == "# keep\nauth required pam_other.so\n")
        rejects { _ = try TouchIDPolicy.replacement(sudo: "", local: nil, enabled: true) }
        rejects { _ = try TouchIDPolicy.replacement(sudo: sudo + rule, local: nil, enabled: false) }
        rejects {
            _ = try TouchIDPolicy.replacement(sudo: sudo, local: "auth required pam_tid.so\n", enabled: true)
        }
        print("PASS: power and Spotlight arguments and pure PAM transforms")
    }

    private static func validateChargeLimit() throws {
        let fixture = """
        Battery level limits:
        (
                {
                Terminated = 0;
                chargeSocLimitDrain = 1;
                chargeSocLimitIsEOC = 1;
                chargeSocLimitNoChargeToFull = 0;
                chargeSocLimitOwner = 236;
                chargeSocLimitReason = manualChargeLimit;
                chargeSocLimitSoc = 80;
            },
                {
                Terminated = 0;
                chargeSocLimitDrain = 1;
                chargeSocLimitIsEOC = 1;
                chargeSocLimitNoChargeToFull = 0;
                chargeSocLimitOwner = 0;
                chargeSocLimitReason = manualChargeLimit;
                chargeSocLimitSoc = 80;
            }
        )
        """
        let current = try NativeChargeLimit.parse(fixture)
        var events: [String] = []
        try NativeChargeLimit.apply(write: { events.append("confirmed") },
            enable: { events.append("enabled") }, restore: { events.append("restored") })
        precondition(events == ["confirmed", "enabled"])
        events = []
        rejects {
            try NativeChargeLimit.apply(write: { events.append("confirmed") }, enable: {
                _ = try NativeChargeLimit.bounded(timeout: .milliseconds(10)) {
                    Thread.sleep(forTimeInterval: 0.1)
                    return true
                }
            }, restore: { events.append("restored") })
        }
        precondition(events == ["confirmed"])
        events = []
        rejects {
            try NativeChargeLimit.apply(write: { events.append("confirmed") },
                enable: { throw FanSMC.Failure.refused }, restore: { events.append("restored") })
        }
        precondition(events == ["confirmed", "restored"])
        events = []
        rejects {
            try NativeChargeLimit.apply(write: { throw FanSMC.Failure.refused },
                enable: { events.append("enabled") }, restore: { events.append("restored") })
        }
        precondition(events == ["restored"])
        let empty = try NativeChargeLimit.parse("No battery level limits set\n")
        let terminated = try NativeChargeLimit.parse(fixture.replacingOccurrences(of: "Terminated = 0",
            with: "Terminated = 1"))
        precondition(current == 80 && empty == nil && terminated == nil)
        rejects { _ = try NativeChargeLimit.parse("unavailable") }
        rejects { _ = try NativeChargeLimit.parse("No battery level limits set\nextra") }
        rejects { _ = try NativeChargeLimit.parse(fixture.replacingOccurrences(of: "Soc = 80", with: "Soc = 101")) }
        print("PASS: native charge limit parser, duplicate limits, off, terminated and invalid output")
    }

    private static func validateBattery() throws {
        final class BatteryFixture: FanSMC.Access {
            var keys: [String: Int] = [:]
            var writes: [String: [UInt8]] = [:]
            var failedProbe: String?

            func info(_ key: String) throws -> FanSMC.Info? {
                if key == failedProbe { throw FanSMC.Failure.refused }
                return keys[key].map { .init(size: $0, type: "ui8 ") }
            }

            func read(_ key: String, info: FanSMC.Info) throws -> [UInt8] {
                [UInt8](repeating: 0, count: info.size)
            }

            func write(_ key: String, bytes: [UInt8]) throws { writes[key] = bytes }
        }
        for keys in [["CHTE": 4, "CHIE": 1], ["CH0B": 1, "CH0C": 1, "CH0I": 1],
                     ["CH0C": 1], ["CHTE": 4, "CH0B": 1, "CH0C": 1, "CHIE": 1, "CH0I": 1]] {
            for off in [false, true] {
                let fixture = BatteryFixture()
                fixture.keys = keys
                try BatterySMC.apply(off ? .batteryChargingOff : .batteryChargingOn, smc: fixture)
                var expected: [String: [UInt8]] = [:]
                if keys["CHTE"] != nil { expected["CHTE"] = [off ? 1 : 0, 0, 0, 0] }
                for key in ["CH0B", "CH0C"] where keys[key] != nil { expected[key] = [off ? 2 : 0] }
                precondition(fixture.writes == expected)
                fixture.writes = [:]
                if keys["CHIE"] != nil || keys["CH0I"] != nil {
                    try BatterySMC.apply(off ? .batteryAdapterOff : .batteryAdapterOn, smc: fixture)
                    expected = [:]
                    if keys["CHIE"] != nil { expected["CHIE"] = [off ? 8 : 0] }
                    if keys["CH0I"] != nil { expected["CH0I"] = [off ? 1 : 0] }
                    precondition(fixture.writes == expected)
                }
            }
        }
        for keys in [[:], ["CHTE": 1], ["CH0B": 1, "CH0C": 4]] {
            let fixture = BatteryFixture()
            fixture.keys = keys
            rejects { try BatterySMC.apply(.batteryChargingOff, smc: fixture) }
            precondition(fixture.writes.isEmpty)
        }
        do {
            try BatterySMC.apply(.batteryChargingOff, smc: BatteryFixture())
            preconditionFailure("Absent keys must report unsupported")
        } catch BatterySMC.Failure.unsupported {
            precondition(RootContract.unsupportedExit != 70)
        }
        let failed = BatteryFixture()
        failed.keys = ["CHTE": 4]
        failed.failedProbe = "CH0B"
        rejects { try BatterySMC.apply(.batteryChargingOff, smc: failed) }
        precondition(failed.writes.isEmpty)
        precondition(BatterySMC.sleepArguments(.batterySleepOn) == ["-a", "disablesleep", "0"])
        precondition(BatterySMC.sleepArguments(.batterySleepOff) == ["-a", "disablesleep", "1"])
        print("PASS: battery byte plans, key probes, preflight failures and sleep arguments (fake SMC only)")
    }

    private static func validateValues() throws {
        let medium = try FanSMC.target(minimum: 1_000, maximum: 6_000, command: .fansMedium)
        let maximum = try FanSMC.target(minimum: 1_000, maximum: 6_000, command: .fansMax)
        precondition(medium == 4_000 && maximum == 6_000)
        for (minimum, maximum) in [(Double.nan, 6_000.0), (-1, 6_000), (1_000, 1_000),
                                    (2_000, 1_000), (0, .infinity), (0, 20_001)] {
            rejects { _ = try FanSMC.target(minimum: minimum, maximum: maximum, command: .fansMedium) }
        }
        let cases: [(String, Int, Double, [UInt8])] = [
            ("flt ", 4, 4_000, [0, 0, 0x7a, 0x45]),
            ("fpe2", 2, 4_000.25, [0x3e, 0x81]),
            ("ui8 ", 1, 1, [1]), ("ui16", 2, 1_234, [4, 0xd2]),
            ("ui32", 4, 0x12345678, [0x12, 0x34, 0x56, 0x78]),
        ]
        for (type, size, value, bytes) in cases {
            let info = FanSMC.Info(size: size, type: type)
            let encoded = try FanSMC.encode(value, info: info)
            let decoded = try FanSMC.decode(bytes, info: info)
            precondition(encoded == bytes && decoded == value)
            for invalid in [Double.nan, .infinity, -1] {
                rejects { _ = try FanSMC.encode(invalid, info: info) }
            }
            rejects { _ = try FanSMC.decode(bytes + [0], info: info) }
        }
        for (type, size, value) in [("flt ", 4, Double.greatestFiniteMagnitude),
                                     ("fpe2", 2, 16_384), ("ui8 ", 1, 256),
                                     ("ui16", 2, 65_536), ("ui32", 4, 4_294_967_296),
                                     ("ui8 ", 1, 0.5), ("nope", 4, 1), ("flt ", 2, 1)] {
            rejects { _ = try FanSMC.encode(value, info: .init(size: size, type: type)) }
        }
        rejects { _ = try FanSMC.decode([0, 0, 0x80, 0x7f], info: .init(size: 4, type: "flt ")) }
    }

    private static func validateSequence() throws {
        let medium = Fixture()
        medium.rejectedModes["F0Md"] = 2
        try medium.controller.run(.fansMedium)
        precondition(medium.writes == ["Ftst=1", "F0Md=1", "F0Md=1", "F0Md=1",
                                       "F0Tg=4000", "F1Md=1", "F1Tg=5000"])
        precondition(medium.pauses == [.milliseconds(100), .milliseconds(100)])
        medium.writes = []
        try medium.controller.run(.fansAuto)
        precondition(medium.writes == ["F0Md=0", "F1Md=0", "Ftst=0"])
        let maximum = Fixture()
        maximum.values["Ftst"] = 1
        maximum.values["F1md"] = maximum.values.removeValue(forKey: "F1Md")
        try maximum.controller.run(.fansMax)
        precondition(maximum.writes == ["F0Md=1", "F0Tg=6000", "F1md=1", "F1Tg=7000"])
        let absentUnlock = Fixture()
        absentUnlock.missing.insert("Ftst")
        try absentUnlock.controller.run(.fansMax)
        precondition(absentUnlock.writes == ["F0Md=1", "F0Tg=6000", "F1Md=1", "F1Tg=7000"])
    }

    private static func validateRecovery() throws {
        for key in ["Ftst", "F0Md", "F0Tg", "F1Md", "F1Tg"] {
            let failed = Fixture()
            failed.failures.insert(key)
            rejects { try failed.controller.run(.fansMax) }
            precondition(Array(failed.writes.suffix(3)) == ["F0Md=0", "F1Md=0", "Ftst=0"])
        }
        let automatic = Fixture()
        automatic.failures.insert("F0Md")
        rejects { try automatic.controller.run(.fansAuto) }
        precondition(automatic.writes == ["F0Md=0", "F1Md=0", "Ftst=0"])
        let timedOut = Fixture()
        timedOut.rejectedModes = ["F0Md": 30, "F1Md": 100]
        rejects { try timedOut.controller.run(.fansMedium) }
        precondition(timedOut.elapsed == .seconds(5))
        precondition(timedOut.writes.contains("F0Tg=4000") && !timedOut.writes.contains("F1Tg=5000"))
        precondition(Array(timedOut.writes.suffix(3)) == ["F0Md=0", "F1Md=0", "Ftst=0"])
        for count in [Double.nan, .infinity, -1, 0, 1.5, 10, Double.greatestFiniteMagnitude] {
            let invalid = Fixture()
            invalid.values["FNum"] = count
            rejects { try invalid.controller.run(.fansMax) }
            precondition(!invalid.writes.contains { $0.hasSuffix("=1") || $0.contains("Tg=") })
            precondition(invalid.writes.last == "Ftst=0")
        }
        for key in ["F0Mn", "F1Mx", "F1Ac", "F1Tg"] {
            let invalid = Fixture()
            invalid.values[key] = 30_000
            rejects { try invalid.controller.run(.fansMedium) }
            precondition(!invalid.writes.contains { $0.hasSuffix("=1") || $0.contains("Tg=") })
        }
        let missingMode = Fixture()
        missingMode.missing.insert("F0Md")
        rejects { try missingMode.controller.run(.fansMax) }
        precondition(missingMode.writes == ["F1Md=0", "Ftst=0"])
        let unreadable = Fixture()
        unreadable.readFailures.insert("F1Mx")
        rejects { try unreadable.controller.run(.fansMax) }
        precondition(unreadable.writes == ["F0Md=0", "F1Md=0", "Ftst=0"])
        let failedProbe = Fixture()
        failedProbe.infoFailures.insert("Ftst")
        rejects { try failedProbe.controller.run(.fansMedium) }
        precondition(failedProbe.writes == ["F0Md=0", "F1Md=0"])
    }
}
#else
@main
struct RootClientTest {
    static func main() async throws {
        validateCommands()
        let strict = ProcessInfo.processInfo.environment["LIBDISPATCH_COOPERATIVE_POOL_STRICT"]
        print("Cooperative pool strict: \(strict ?? "unset")")
        if ProcessInfo.processInfo.environment["NOTCHCAST_TEST_HELPER_EXECUTABLE"] == "1" {
            try validateExecutable()
        }
        try validatePaths()
        try await validateProcessLifetime()
        print("PASS: root commands, replies, path ownership and permissions, timeouts and cancellation")
    }

    private static func validateCommands() {
        for command in RootContract.Command.allCases {
            precondition(RootContract.Command(arguments: command.arguments) == command)
            let read = command.operation == .read
            let spotlight = command == .spotlightOn || command == .spotlightOff
            precondition(command.operation == (read ? .read : spotlight ? .spotlight : .change))
            precondition(command.operation.timeout == .seconds(read ? 3 : spotlight ? 60 : 12))
            precondition(RootContract.Reply(command: command, output: command.output) != nil)
            precondition(RootContract.Reply(command: command, output: command.output + "extra") == nil)
            precondition(RootContract.Reply(command: command, output: "") == nil)
            precondition(RootContract.Command(arguments: command.arguments + ["extra"]) == nil)
            if !read {
                precondition(command.output == "ok\n")
                precondition(RootContract.Reply(command: command, output: "ok\n") == .ok)
                precondition(RootContract.Reply(command: command, output: "ok") == nil)
                precondition(RootContract.Reply(command: command, output: "pong\n") == nil)
            }
        }
        let invalid: [[String]] = [
            [], [""], ["evil"], ["--help"], ["VERSION"], ["version", "extra"],
            ["ping", "extra"], ["version;id"], ["$(id)"], ["/bin/sh"], ["ping\n"],
            ["charging", "on"], ["sleep", "disable"], ["fan", "set", "1"], ["version\0"],
        ]
        for arguments in invalid {
            precondition(RootContract.Command(arguments: arguments) == nil)
        }
        precondition(RootContract.version == "3")
        precondition(RootContract.Reply(command: .version, output: "3\n") == .version("3"))
        do {
            try RootHelperClient.validateExitStatus(78)
            preconditionFailure("Caller rejection must require reinstall")
        } catch {
            precondition(error as? RootHelperClient.Failure == .reinstallRequired)
        }
        precondition(RootContract.Reply(command: .version, output: "2\n") == .version("2"))
        for invalid in [" 2 \n\n", "2", "02\n", "2\n\n", "+2\n"] {
            precondition(RootContract.Reply(command: .version, output: invalid) == nil)
        }
        precondition(RootContract.Reply(command: .ping, output: "pong") == nil)
        precondition(RootContract.Command.chargeLimitRead.operation == .read)
        precondition(RootContract.Reply(command: .chargeLimitRead, output: "80\n") == .chargeLimit(80))
        precondition(RootContract.Reply(command: .chargeLimitRead, output: "off\n") == .chargeLimit(nil))
        for invalid in ["0\n", "101\n", "080\n", "80", "80\nextra"] {
            precondition(RootContract.Reply(command: .chargeLimitRead, output: invalid) == nil)
        }
        precondition(RootContract.Operation.change.timeout == .seconds(12))
    }

    private static func validateExecutable() throws {
        precondition(geteuid() != 0, "Never exercise change verbs as root in this harness")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchcast-helper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("helper")
        let sources = try FileManager.default.contentsOfDirectory(atPath: "notchcast/root")
            .filter { $0.hasSuffix(".swift") }.sorted().map { "notchcast/root/\($0)" }
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                              "-warnings-as-errors", "-O"] + sources + ["-o", helper.path]
        try compiler.run()
        compiler.waitUntilExit()
        precondition(compiler.terminationStatus == 0, "Helper compilation failed")

        for (arguments, expected): ([String], Int32) in [
            (["invalid"], 64), (["charge-limit-80"], 78), (["fans-auto"], 78),
        ] {
            let process = Process()
            process.executableURL = helper
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            precondition(process.terminationReason == .exit && process.terminationStatus == expected)
        }
        let fanTests = directory.appendingPathComponent("fan-tests")
        let fanCompiler = Process()
        fanCompiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        fanCompiler.arguments = ["swiftc", "-swift-version", "6", "-strict-concurrency=complete",
                                 "-warnings-as-errors", "-D", "FAN_SMC_TEST", "-parse-as-library",
                                 "notchcast/root/RootContract.swift", "notchcast/root/FanSMC.swift",
                                 "notchcast/root/BatterySMC.swift",
                                 "notchcast/root/NativeChargeLimit.swift",
                                 "notchcast/root/Power.swift",
                                 "notchcast/root/Spotlight.swift", "notchcast/root/TouchIDPolicy.swift",
                                 "Tests/notchcast-root-client-test.swift", "-o", fanTests.path]
        try fanCompiler.run()
        fanCompiler.waitUntilExit()
        precondition(fanCompiler.terminationStatus == 0, "Fan fixture compilation failed")
        let test = Process()
        test.executableURL = fanTests
        try test.run()
        test.waitUntilExit()
        precondition(test.terminationReason == .exit && test.terminationStatus == 0)
    }

    private static func validatePaths() throws {
        precondition(getuid() != 0, "Run this harness as your ordinary user")
        precondition(RootToolPath.verify("/usr/bin/true") == nil)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchcast-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("helper")
        try Data("fixture".utf8).write(to: file)
        precondition(chmod(file.path, 0o755) == 0)
        precondition(RootToolPath.check(file.path, directory: false) == .wrongOwner(file.path))
        precondition(RootToolPath.check(directory.path, directory: true) == .wrongOwner(directory.path))
        precondition(RootToolPath.verify(file.path) != nil)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        precondition(RootToolPath.check(link.path, directory: false) == .wrongKind(link.path))
        let absent = directory.appendingPathComponent("absent").path
        precondition(RootToolPath.check(absent, directory: false) == .missing(absent))
        for path in ["relative/helper", "/", "/Library//helper", "/Library/../helper", "/Library/./helper"] {
            precondition(RootToolPath.verify(path) == .wrongKind(path))
        }

        var info = stat()
        info.st_uid = 0
        info.st_mode = S_IFREG | 0o755
        precondition(RootToolPath.problem(path: "helper", info: info, directory: false) == nil)
        for permissions: mode_t in [0o775, 0o757, 0o777] {
            info.st_mode = S_IFREG | permissions
            precondition(RootToolPath.problem(path: "helper", info: info, directory: false) == .writable("helper"))
        }
        info.st_mode = S_IFREG | 0o644
        precondition(RootToolPath.problem(path: "helper", info: info, directory: false) == .notExecutable("helper"))
        info.st_mode = S_IFDIR | 0o755
        precondition(RootToolPath.problem(path: "parent", info: info, directory: true) == nil)
        info.st_mode = S_IFDIR | 0o775
        precondition(RootToolPath.problem(path: "parent", info: info, directory: true) == .writable("parent"))
        info.st_mode = S_IFLNK | 0o755
        precondition(RootToolPath.problem(path: "parent", info: info, directory: true) == .wrongKind("parent"))
    }

    private static func validateProcessLifetime() async throws {
        let fast = sleeper("0.01")
        let fastExit = try fast.runObservingExit()
        try await RootHelperClient.wait(for: fast, exit: fastExit, timeout: .seconds(1))
        precondition(!fast.isRunning && fast.terminationStatus == 0)

        let slow = sleeper("10")
        let slowExit = try slow.runObservingExit()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await RootHelperClient.wait(for: slow, exit: slowExit, timeout: .milliseconds(50))
            preconditionFailure("A slow helper must time out")
        } catch RootHelperClient.Failure.timedOut {
            precondition(!slow.isRunning)
            precondition(start.duration(to: clock.now) < .seconds(2))
        }

        let cancelled = sleeper("10")
        let cancelledExit = try cancelled.runObservingExit()
        let task = Task {
            try await RootHelperClient.wait(for: cancelled, exit: cancelledExit, timeout: .seconds(3))
        }
        task.cancel()
        do {
            try await task.value
            preconditionFailure("Cancellation must propagate")
        } catch is CancellationError {
            precondition(!cancelled.isRunning)
        }
    }

    private static func sleeper(_ seconds: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        process.environment = [:]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}
#endif
