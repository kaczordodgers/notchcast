import Darwin
import Foundation
import Security

enum RootCaller {
    static func permits(_ command: RootContract.Command, identity: () -> Bool) -> Bool {
        command == .version || command == .ping || identity()
    }

    static func authorized() -> Bool {
        let sudoPID = getppid()
        guard let sudo = snapshot(sudoPID),
              matches(sudoPID, requirement: "anchor apple and identifier com.apple.sudo"),
              let app = snapshot(pid_t(sudo.pbi_ppid)), let requirement = appRequirement(),
              matches(pid_t(sudo.pbi_ppid), requirement:
                requirement,
                hardened: true),
              let sudoAfter = snapshot(sudoPID), let appAfter = snapshot(pid_t(sudo.pbi_ppid))
        else { return false }
        return getppid() == sudoPID && same(sudo, sudoAfter) && same(app, appAfter)
    }

    private static func same(_ first: proc_bsdinfo, _ second: proc_bsdinfo) -> Bool {
        first.pbi_pid == second.pbi_pid && first.pbi_ppid == second.pbi_ppid
            && first.pbi_start_tvsec == second.pbi_start_tvsec
            && first.pbi_start_tvusec == second.pbi_start_tvusec
    }

    private static func snapshot(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout.size(ofValue: info))
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    static func appRequirement(pin: String? = CallerRequirement.leafSHA1) -> String? {
        guard let pin, pin.count == 40, pin.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { return nil }
        return "identifier app.notchcast and certificate leaf = H\"\(pin)\""
    }

    static func matches(_ pid: pid_t, requirement: String, hardened: Bool = false) -> Bool {
        var port: mach_port_t = 0
        guard task_name_for_pid(mach_task_self_, pid, &port) == KERN_SUCCESS else { return false }
        defer { mach_port_deallocate(mach_task_self_, port) }
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: token) / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &token) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(port, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return false }
        let data = withUnsafeBytes(of: token) { Data($0) }
        var code: SecCode?
        var rule: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary,
                                            [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &rule) == errSecSuccess,
              let rule, SecCodeCheckValidity(code, [], rule) == errSecSuccess else { return false }
        guard hardened else { return true }
        var information: CFDictionary?
        // Security accepts dynamic guests here despite the imported static-code parameter type.
        let guest = unsafeBitCast(code, to: SecStaticCode.self)
        guard SecCodeCopySigningInformation(guest,
                                           SecCSFlags(rawValue: kSecCSDynamicInformation | kSecCSSigningInformation),
                                           &information) == errSecSuccess,
              let values = information as? [String: Any],
              let flags = values[kSecCodeInfoStatus as String] as? UInt32,
              flags & 0x10001 == 0x10001,
              flags & 0x10000004 == 0 else { return false }
        let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        return !["com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation",
                 "com.apple.security.cs.allow-dyld-environment-variables"].contains {
            entitlements[$0] as? Bool == true
        }
    }
}
