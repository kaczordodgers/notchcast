import Darwin
import Foundation
import SystemConfiguration

@MainActor
final class NetMergeInterfaceMonitor {
    enum Failure: Error { case dynamicStoreUnavailable }

    func readInterfaces() throws -> [NetMergePolicy.Interface] {
        guard let store = SCDynamicStoreCreate(nil, "NetMergeRead" as CFString, nil, nil),
              let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]
        else { throw Failure.dynamicStoreUnavailable }
        return interfaces.compactMap { interface in
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String? else { return nil }
            let kind: NetMergePolicy.Interface.Kind
            if SCNetworkInterfaceGetInterfaceType(interface) == kSCNetworkInterfaceTypeIEEE80211 {
                kind = .wifi
            } else if Self.isIPhoneUSB(SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? "") {
                kind = .iPhoneUSB
            } else {
                return nil
            }
            let key = "State:/Network/Interface/\(name)/IPv4"
            let state = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
            let addresses = state?[kSCPropNetIPv4Addresses as String] as? [String] ?? []
            return .init(bsdName: name, kind: kind, hasIPv4: addresses.contains(where: Self.isUsableIPv4))
        }
    }

    static func isIPhoneUSB(_ hardwarePort: String) -> Bool {
        let words = hardwarePort.lowercased().split { !$0.isLetter && !$0.isNumber }
        return words.contains("iphone") && words.contains("usb")
    }

    static func isUsableIPv4(_ text: String) -> Bool {
        var address = in_addr()
        guard inet_pton(AF_INET, text, &address) == 1 else { return false }
        let value = UInt32(bigEndian: address.s_addr)
        return value != 0 && value >> 24 != 127 && value >> 16 != 0xA9FE && value >> 24 < 224
    }

}
