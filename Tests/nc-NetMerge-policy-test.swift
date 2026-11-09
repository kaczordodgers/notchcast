import Foundation

@main
struct NetMergePolicyTest {
    @MainActor
    static func main() throws {
        typealias Interface = NetMergePolicy.Interface
        let wifi = Interface(bsdName: "en0", kind: .wifi, hasIPv4: true)
        let phone = Interface(bsdName: "en7", kind: .iPhoneUSB, hasIPv4: true)
        let interfaces = [phone, wifi]
        func decision(_ kind: NetMergePolicy.JobKind, _ size: Int64?, _ enabled: Bool = true) -> NetMergePolicy.Decision {
            NetMergePolicy.evaluate(interfaces: interfaces, kind: kind, sizeBytes: size, enabled: enabled)
        }
        assert(decision(.torrent, nil).aria2Arguments == ["--multiple-interface=en0,en7"])
        assert(decision(.torrent, nil).usesIPhone)
        assert(decision(.torrent, 0).usesIPhone)
        assert(!decision(.torrent, nil, false).usesIPhone)
        for size: Int64? in [nil, -1, 0, 199_999_999, 200_000_000] {
            assert(!decision(.download, size).usesIPhone)
        }
        assert(decision(.download, 200_000_001).usesIPhone)
        for missing in [[], [wifi], [phone], [wifi, Interface(bsdName: "en7", kind: .iPhoneUSB, hasIPv4: false)],
                        [phone, Interface(bsdName: "en0", kind: .wifi, hasIPv4: false)],
                        [wifi, Interface(bsdName: "en0", kind: .iPhoneUSB, hasIPv4: true)],
                        [wifi, Interface(bsdName: "en7,en8", kind: .iPhoneUSB, hasIPv4: true)]] {
            let result = NetMergePolicy.evaluate(interfaces: missing, kind: .torrent, sizeBytes: nil, enabled: true)
            assert(result.aria2Arguments.isEmpty && !result.usesIPhone)
        }
        for name in ["iPhone USB", "iPhone (USB)", "IPHONE USB"] {
            assert(NetMergeInterfaceMonitor.isIPhoneUSB(name))
        }
        for name in ["iPhone", "USB Ethernet", "Wi-Fi", "iPhone Wi-Fi"] {
            assert(!NetMergeInterfaceMonitor.isIPhoneUSB(name))
        }
        for address in ["192.168.1.2", "172.20.10.2", "10.0.0.1"] {
            assert(NetMergeInterfaceMonitor.isUsableIPv4(address))
        }
        for address in ["", "::1", "0.0.0.0", "127.0.0.1", "169.254.1.2", "255.255.255.255", "bad"] {
            assert(!NetMergeInterfaceMonitor.isUsableIPv4(address))
        }
        let monitor = NetMergeInterfaceMonitor()
        _ = try monitor.readInterfaces()
        print("NetMerge: policy boundaries, interface eligibility, snapshot stability and on-demand read passed")
    }
}
