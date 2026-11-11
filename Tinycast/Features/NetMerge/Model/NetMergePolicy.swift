import Foundation

enum NetMergePolicy {
    struct Interface: Equatable, Sendable {
        enum Kind: Sendable { case wifi, iPhoneUSB }

        let bsdName: String
        let kind: Kind
        let hasIPv4: Bool
    }

    enum JobKind: Sendable { case torrent, download }

    struct Decision: Equatable, Sendable {
        let aria2Arguments: [String]
        let usesIPhone: Bool
    }

    static let bigDownloadBytes: Int64 = 200_000_000
    /// The aria2 flag that names a Wi-Fi and iPhone pair; every reader goes through `interfaceNames`.
    static let interfaceFlag = "--multiple-interface="

    static func interfaceNames(in arguments: [String]) -> [String] {
        guard let flag = arguments.first(where: { $0.hasPrefix(interfaceFlag) }) else { return [] }
        return flag.dropFirst(interfaceFlag.count).split(separator: ",").map(String.init)
    }

    static func evaluate(
        interfaces: [Interface], kind: JobKind, sizeBytes: Int64?, enabled: Bool
    ) -> Decision {
        let unused = Decision(aria2Arguments: [], usesIPhone: false)
        guard enabled, kind == .torrent || (sizeBytes ?? 0) > bigDownloadBytes else { return unused }
        let usable = interfaces.filter { interface in
            interface.hasIPv4 && !interface.bsdName.isEmpty
                && interface.bsdName.utf8.allSatisfy {
                    (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                }
        }.sorted { $0.bsdName < $1.bsdName }
        guard let wifi = usable.first(where: { $0.kind == .wifi }),
              let phone = usable.first(where: { $0.kind == .iPhoneUSB && $0.bsdName != wifi.bsdName })
        else { return unused }
        return Decision(
            aria2Arguments: [interfaceFlag + "\(wifi.bsdName),\(phone.bsdName)"], usesIPhone: true
        )
    }
}
