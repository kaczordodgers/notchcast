// notchcast-sources: Tinycast/Features/Downloads/Media/MediaArguments.swift
// notchcast-sources: Tinycast/Features/Downloads/Media/MediaNetwork.swift Tinycast/Features/NetMerge/Model/*.swift
import Foundation

@main
struct MediaNetworkTest {
    static func main() {
        let wifi = NetMergePolicy.Interface(bsdName: "en0", kind: .wifi, hasIPv4: true)
        let phone = NetMergePolicy.Interface(bsdName: "en7", kind: .iPhoneUSB, hasIPv4: true)
        for (json, interfaces, enabled, expected) in [
            (#"{"filesize":200000000}"#, [wifi, phone], true, false),
            (#"{"filesize":200000001}"#, [wifi, phone], true, true),
            (#"{"filesize_approx":300000000}"#, [wifi], true, false),
            (#"{"filesize":300000000}"#, [wifi, phone], false, false),
            (#"{}"#, [wifi, phone], true, false)
        ] {
            let decision = NetMergePolicy.evaluate(interfaces: interfaces, kind: .download,
                sizeBytes: MediaNetwork.expectedSize(json), enabled: enabled)
            assert(decision.usesIPhone == expected)
            let args = MediaArguments.download(source: "https://example.com", destination: URL(filePath: "/tmp"),
                format: .video, aria2Path: "/fake/aria2c", networkArguments: decision.aria2Arguments)
            assert(args.contains(where: { $0.contains("--multiple-interface=en0,en7") }) == expected)
        }
        let combined = #"{"requested_formats":[{"filesize":150000000},{"filesize_approx":60000000}]}"#
        assert(MediaNetwork.expectedSize(combined) == 210000000)
        assert(MediaNetwork.expectedSize(#"{"requested_formats":[{"filesize":300000000},{}]}"#) == nil)
        print("Media network: small, big, missing iPhone, disabled and unknown sizes passed")
    }
}
