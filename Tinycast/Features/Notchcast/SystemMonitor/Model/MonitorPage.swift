import Foundation

/// The System page (#977) as island values: four tiles, the busiest processes, its Home line and the hot glyph.
enum MonitorPage {
    static let id = "system"
    static let symbol = "cpu"
    /// After Agents (0) and Player (10), before Day (30), as decision 946-11 orders them.
    static let order = 20
    static let dash = "–"

    static func page(_ board: MonitorBoard, locale: Locale) -> IslandPage {
        let sample = board.sample
        let heat = board.heat
        let tiles = IslandCardGroup(
            title: String(localized: "Resources", table: "NotchcastSystemMonitor"),
            cards: [
                cpuCard(sample, hot: heat.isHot(.cpu), locale: locale),
                memoryCard(sample, hot: heat.isHot(.memory), locale: locale),
                diskCard(sample, hot: heat.isHot(.disk), locale: locale),
                networkCard(sample, locale: locale),
            ])
        return IslandPage(
            id: id, title: String(localized: "System", table: "NotchcastSystemMonitor"), symbol: symbol,
            order: order, line: line(board, locale: locale),
            blocks: [.cards(tiles)] + (disks(board, locale: locale) + processes(sample, locale: locale))
                .map(IslandPageBlock.row))
    }

    /// The first hot resource, else the busier of CPU and memory, with the busiest process beside it.
    static func line(_ board: MonitorBoard, locale: Locale) -> IslandPageLine {
        let sample = board.sample
        if let resource = board.heat.hot.first {
            return IslandPageLine(symbol: symbol(resource), text: label(resource),
                                  detail: value(resource, sample, locale: locale), tone: .warning)
        }
        let loads: [(MonitorResource, Double)] = [
            sample.cpu.map { (.cpu, $0) }, sample.memory.map { (.memory, $0.fraction) },
        ].compactMap(\.self)
        guard let busiest = loads.max(by: { $0.1 < $1.1 }) else {
            return IslandPageLine(symbol: symbol, text: String(localized: "Measuring…", table: "NotchcastSystemMonitor"))
        }
        let amount = percent(busiest.1, locale)
        let words = busiest.0 == .cpu ? String(localized: "CPU \(amount)", table: "NotchcastSystemMonitor")
            : String(localized: "Memory \(amount)", table: "NotchcastSystemMonitor")
        let top = sample.processes?.first.map { "\($0.name) \(percent($0.cpu, locale))" }
        return IslandPageLine(symbol: symbol(busiest.0), text: words, detail: top)
    }

    /// The closed island's glyph while anything runs hot: the first hot resource's symbol and one short word.
    static func status(_ heat: MonitorHeat) -> IslandStatus? {
        guard let first = heat.hot.first else { return nil }
        let word = switch first {
        case .cpu: String(localized: "Hot", table: "NotchcastSystemMonitor")
        case .memory: String(localized: "High", table: "NotchcastSystemMonitor")
        default: String(localized: "Full", table: "NotchcastSystemMonitor")
        }
        return IslandStatus(id: id, symbol: symbol(first), text: word,
                            label: heat.hot.map(label).joined(separator: ", "), tone: .warning)
    }

    static func symbol(_ resource: MonitorResource) -> String {
        switch resource {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        }
    }

    static func label(_ resource: MonitorResource) -> String {
        switch resource {
        case .cpu: String(localized: "CPU running hot", table: "NotchcastSystemMonitor")
        case .memory: String(localized: "Memory pressure critical", table: "NotchcastSystemMonitor")
        case .disk: String(localized: "Startup disk almost full", table: "NotchcastSystemMonitor")
        case .network: String(localized: "Network", table: "NotchcastSystemMonitor")
        }
    }

    private static func value(_ resource: MonitorResource, _ sample: MonitorSample, locale: Locale) -> String? {
        switch resource {
        case .cpu: sample.cpu.map { percent($0, locale) }
        case .memory: sample.memory.map { percent($0.fraction, locale) }
        case .disk: sample.disk.map { free($0, locale) }
        case .network: nil
        }
    }

    static func cpuCard(_ sample: MonitorSample, hot: Bool, locale: Locale) -> IslandCard {
        let meter = IslandCardMeter(
            label: String(localized: "Load", table: "NotchcastSystemMonitor"),
            value: sample.cpu.map { percent($0, locale) } ?? dash, fraction: sample.cpu ?? 0, thick: true,
            warning: hot, note: hot ? String(localized: "Running hot", table: "NotchcastSystemMonitor") : nil)
        return IslandCard(title: String(localized: "CPU", table: "NotchcastSystemMonitor"), body: .meters([meter]),
                          dimmed: sample.cpu == nil)
    }

    static func memoryCard(_ sample: MonitorSample, hot: Bool, locale: Locale) -> IslandCard {
        let memory = sample.memory
        let meter = IslandCardMeter(
            label: String(localized: "Used", table: "NotchcastSystemMonitor"),
            value: memory.map { bytes($0.used, locale, memory: true) } ?? dash,
            trailing: memory.map { of(bytes($0.total, locale, memory: true)) }, fraction: memory?.fraction ?? 0,
            thick: true, warning: hot,
            note: hot ? String(localized: "Pressure critical", table: "NotchcastSystemMonitor") : nil)
        return IslandCard(title: String(localized: "Memory", table: "NotchcastSystemMonitor"),
                          body: .meters([meter]), dimmed: memory == nil)
    }

    static func diskCard(_ sample: MonitorSample, hot: Bool, locale: Locale) -> IslandCard {
        let disk = sample.disk
        let meter = IslandCardMeter(
            label: String(localized: "Used", table: "NotchcastSystemMonitor"),
            value: disk.map { bytes($0.used, locale) } ?? dash, trailing: disk.map { of(bytes($0.total, locale)) },
            fraction: disk?.fraction ?? 0, thick: true, warning: hot,
            note: hot ? String(localized: "Almost full", table: "NotchcastSystemMonitor") : nil)
        return IslandCard(title: String(localized: "Disk", table: "NotchcastSystemMonitor"), body: .meters([meter]),
                          dimmed: disk == nil, caption: disk.map { free($0, locale) })
    }

    static func networkCard(_ sample: MonitorSample, locale: Locale) -> IslandCard {
        let title = String(localized: "Network", table: "NotchcastSystemMonitor")
        guard let down = sample.down, let up = sample.up else {
            let measuring = String(localized: "Measuring…", table: "NotchcastSystemMonitor")
            return IslandCard(title: title, body: .notice(symbol: nil, headline: measuring, detail: nil))
        }
        let (inbound, outbound) = (rate(down, locale), rate(up, locale))
        return IslandCard(
            title: title,
            body: .notice(symbol: nil, headline: String(localized: "↓ \(inbound)", table: "NotchcastSystemMonitor"),
                          detail: String(localized: "↑ \(outbound)", table: "NotchcastSystemMonitor")),
            spoken: String(localized: "Network. Download \(inbound), upload \(outbound)", table: "NotchcastSystemMonitor"))
    }

    private static func disks(_ board: MonitorBoard, locale: Locale) -> [IslandPageRow] {
        let volumes = board.sample.volumes
        guard !volumes.isEmpty else { return [] }
        var rows = [IslandPageRow(title: String(localized: "Disks", table: "NotchcastSystemMonitor"))]
        rows += volumes.prefix(MonitorVolumes.rowLimit).map { volume in
            let name = volume.name
            let size = volume.size.map { bytes($0, locale) } ?? dash
            let ejecting = board.ejecting.contains(volume.path)
            return IslandPageRow(
                id: ejecting ? nil : MonitorVolumes.action(for: volume.path), symbol: "externaldrive",
                title: name, detail: size, trailing: ejecting
                    ? String(localized: "Ejecting…", table: "NotchcastSystemMonitor")
                    : String(localized: "Eject", table: "NotchcastSystemMonitor"),
                spoken: ejecting ? String(localized: "Ejecting \(name)", table: "NotchcastSystemMonitor")
                    : String(localized: "Eject \(name), \(size)", table: "NotchcastSystemMonitor"))
        }
        let more = volumes.count - MonitorVolumes.rowLimit
        if more > 0 {
            rows.append(IslandPageRow(title: String(localized: "\(more) more", table: "NotchcastSystemMonitor")))
        }
        return rows
    }

    static func ejectNotice(_ outcome: MonitorEjectOutcome, volume: MonitorVolume) -> IslandNotice {
        let id = MonitorVolumes.action(for: volume.path)
        let name = volume.name
        let text: String
        switch outcome {
        case .ejected:
            return IslandNotice(id: id, symbol: "checkmark",
                                text: String(localized: "Ejected \(name)", table: "NotchcastSystemMonitor"))
        case .busy(let holder?):
            text = String(localized: "\(name) Is in Use by \(holder)", table: "NotchcastSystemMonitor")
        case .busy(nil):
            text = String(localized: "\(name) Is in Use", table: "NotchcastSystemMonitor")
        case .failed:
            text = String(localized: "Couldn’t Eject \(name)", table: "NotchcastSystemMonitor")
        }
        return IslandNotice(id: id, symbol: "externaldrive.badge.exclamationmark", text: text, isFailure: true)
    }

    /// A header, then the busiest processes by CPU with their memory; "Measuring…" until two reads.
    static func processes(_ sample: MonitorSample, locale: Locale) -> [IslandPageRow] {
        let header = IslandPageRow(title: String(localized: "Top processes", table: "NotchcastSystemMonitor"))
        guard let processes = sample.processes else {
            return [header, IslandPageRow(title: String(localized: "Measuring…", table: "NotchcastSystemMonitor"))]
        }
        return [header] + processes.map {
            IslandPageRow(title: $0.name, detail: bytes($0.footprint, locale, memory: true),
                          trailing: percent($0.cpu, locale))
        }
    }

    static func percent(_ fraction: Double, _ locale: Locale) -> String {
        min(max(fraction, 0), 1).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// Memory counts in binary units as Activity Monitor does; disks and speeds in decimal as Finder does.
    static func bytes(_ count: UInt64, _ locale: Locale, memory: Bool = false) -> String {
        Int64(clamping: count).formatted(.byteCount(style: memory ? .memory : .file, spellsOutZero: false).locale(locale))
    }

    static func rate(_ perSecond: Double, _ locale: Locale) -> String {
        let count = perSecond.isFinite ? UInt64(max(0, perSecond)) : 0
        return String(localized: "\(bytes(count, locale))/s", table: "NotchcastSystemMonitor")
    }

    private static func free(_ disk: MonitorDisk, _ locale: Locale) -> String {
        String(localized: "\(bytes(disk.free, locale)) free", table: "NotchcastSystemMonitor")
    }

    private static func of(_ total: String) -> String {
        String(localized: "of \(total)", table: "NotchcastSystemMonitor")
    }
}
