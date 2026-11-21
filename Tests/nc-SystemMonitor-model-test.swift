// notchcast-sources: Tinycast/Features/Notchcast/SystemMonitor/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tests/nc-SystemMonitor-fixtures.swift
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-SystemMonitor-model-test: \(message)") }
}

/// #977's thresholds, hot-state decisions, rates and page, from injected readings.
@main
struct SystemMonitorModelTests {
    typealias Fix = MonitorFixtures

    static func main() {
        counters()
        cpuHold()
        cpuCools()
        memoryAndDisk()
        diskBounds()
        rates()
        cadence()
        processes()
        gaps()
        page()
        volumes()
        ejecting()
        hotPage()
        homeLine()
        tones()
        print("PASSED")
    }

    static func counters() {
        let before = MonitorCPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        check(MonitorCPUTicks(user: 160, system: 80, idle: 910, nice: 10).load(since: before) == 0.625,
              "busy over all ticks between two reads")
        check(before.load(since: before) == nil, "no ticks passed, no load")
        let memory = MonitorMemory(total: 16 * Fix.gib, pageSize: 16384, internalPages: 400_000, purgeablePages: 50_000,
                                   wiredPages: 100_000, compressorPages: 50_000)
        check(memory?.used == 500_000 * 16384, "app (internal less purgeable) + wired + compressed")
        check(MonitorMemory(total: 0, pageSize: 16384, internalPages: 1, purgeablePages: 0, wiredPages: 0,
                            compressorPages: 0) == nil, "no total, no reading")
        let disk = MonitorDisk(total: 500, rawFree: 40, importantFree: 60)
        check(disk?.free == 60 && disk?.used == 440, "purgeable space counts as free")
        check(MonitorDisk(total: 500, rawFree: 80, importantFree: 60)?.free == 80, "never less than raw free")
        check(MonitorDisk(total: 500, rawFree: nil, importantFree: nil) == nil, "no free reading, no disk")
        check(MonitorPressure(kernelLevel: 4) == .critical && MonitorPressure(kernelLevel: 9) == .unknown,
              "kernel pressure levels")
        check(MonitorNetworkCounters.counts("en0") && !MonitorNetworkCounters.counts("utun3")
              && !MonitorNetworkCounters.counts("lo0") && !MonitorNetworkCounters.counts("awdl0"),
              "only physical interfaces count")
    }

    /// A burst is not hot: CPU must stay at or above 90 % for 12 s of fresh reads.
    static func cpuHold() {
        var heat = MonitorHeat()
        heat.update(cpu: 0.95, readAt: 100, pressure: .normal, disk: nil)
        check(!heat.isHot(.cpu), "one read over the limit proves nothing")
        heat.update(cpu: 0.97, readAt: 106, pressure: .normal, disk: nil)
        check(!heat.isHot(.cpu), "6 s is not yet 12")
        heat.update(cpu: 0.80, readAt: 108, pressure: .normal, disk: nil)
        heat.update(cpu: 0.95, readAt: 112, pressure: .normal, disk: nil)
        check(!heat.isHot(.cpu), "a dip under the limit restarts the hold")
        heat.update(cpu: 0.95, readAt: 124, pressure: .normal, disk: nil)
        check(heat.hot == [.cpu], "12 s held over the limit runs hot")
        var background = MonitorHeat()
        background.update(cpu: 0.9, readAt: 0, pressure: .normal, disk: nil)
        background.update(cpu: 0.9, readAt: 15, pressure: .normal, disk: nil)
        check(background.isHot(.cpu), "two hidden reads 15 s apart at exactly 90 % run hot")
        var failed = MonitorHeat()
        failed.update(cpu: 0.99, readAt: 0, pressure: .normal, disk: nil)
        failed.update(cpu: nil, readAt: 6, pressure: .normal, disk: nil)
        failed.update(cpu: 0.99, readAt: 12, pressure: .normal, disk: nil)
        check(!failed.isHot(.cpu), "a failed read restarts the hold rather than counting as hot")
    }

    /// Once hot, CPU stays hot until it falls under 75 %, so the glyph never flickers at the limit.
    static func cpuCools() {
        var heat = MonitorHeat()
        heat.update(cpu: 0.95, readAt: 0, pressure: .normal, disk: nil)
        heat.update(cpu: 0.95, readAt: 12, pressure: .normal, disk: nil)
        heat.update(cpu: 0.80, readAt: 14, pressure: .normal, disk: nil)
        check(heat.isHot(.cpu), "between the marks it stays hot")
        heat.update(cpu: 0.74, readAt: 16, pressure: .normal, disk: nil)
        check(!heat.isHot(.cpu), "under 75 % it cools")
        heat.update(cpu: 0.95, readAt: 18, pressure: .normal, disk: nil)
        check(!heat.isHot(.cpu), "and must hold 12 s again")
    }

    static func memoryAndDisk() {
        var heat = MonitorHeat()
        heat.update(cpu: 0.1, readAt: 0, pressure: .warning, disk: Fix.disk(freePercent: 20))
        check(heat.hot.isEmpty, "warning pressure and 20 % free are not hot")
        heat.update(cpu: 0.1, readAt: 2, pressure: .critical, disk: Fix.disk(freePercent: 9))
        check(heat.hot == [.memory], "9 % of 500 GB is 45 GB free: a big disk is not full on a percent alone")
        heat.update(cpu: 0.1, readAt: 4, pressure: .critical, disk: Fix.disk(freePercent: 3))
        check(heat.hot == [.memory, .disk], "critical pressure and 15 GB free run hot, in island order")
        heat.update(cpu: 0.1, readAt: 6, pressure: .unknown, disk: Fix.disk(freePercent: 4))
        check(heat.hot == [.disk], "20 GB free stays hot until 24 GB; unknown pressure is not hot")
        var small = MonitorHeat()
        small.update(cpu: nil, readAt: 0, pressure: .normal, disk: MonitorDisk(total: 8 * Fix.gb, rawFree: 0,
                                                                               importantFree: nil))
        check(small.hot.isEmpty, "a volume under 10 GB never counts as nearly full")
        var all = MonitorHeat()
        all.update(cpu: 1, readAt: 0, pressure: .critical, disk: Fix.disk(freePercent: 1))
        all.update(cpu: 1, readAt: 12, pressure: .critical, disk: Fix.disk(freePercent: 1))
        check(all.hot == [.cpu, .memory, .disk], "CPU leads, then memory, then disk")
    }

    /// Hot needs both under 10 % and under 20 GB free; it holds until 12 % or 24 GB is free.
    static func diskBounds() {
        func hot(_ total: UInt64, _ free: UInt64, after first: UInt64? = nil) -> Bool {
            var heat = MonitorHeat()
            for free in [first, free].compactMap(\.self) {
                heat.update(cpu: nil, readAt: 0, pressure: .normal,
                            disk: MonitorDisk(total: total, rawFree: free, importantFree: nil))
            }
            return heat.isHot(.disk)
        }
        let gb = Fix.gb
        check(!hot(150 * gb, 15 * gb) && hot(150 * gb, 15 * gb - 1), "under 10 % of a 150 GB disk, at 10 % not")
        check(!hot(500 * gb, 20 * gb) && hot(500 * gb, 20 * gb - 1), "under 20 GB of a 500 GB disk, at 20 GB not")
        check(!hot(1000 * gb, 90 * gb), "9 % of 1 TB is plenty")
        check(hot(150 * gb, 18 * gb - 1, after: 14 * gb) && !hot(150 * gb, 18 * gb, after: 14 * gb),
              "once hot, a small disk clears at 12 % free")
        check(hot(500 * gb, 24 * gb - 1, after: 19 * gb) && !hot(500 * gb, 24 * gb, after: 19 * gb),
              "once hot, a big disk clears at 24 GB free")
    }

    /// Shown, a read that only set a baseline is followed in half a second, then every 2 s; hidden every 15 s.
    static func cadence() {
        var board = MonitorBoard()
        check(board.interval(shown: true) == .seconds(2) && board.interval(shown: false) == .seconds(15), "at rest")
        board.apply(Fix.reading(at: 0, busy: 0, total: 1000, received: 0, sent: 0, detail: false),
                    processorCount: 4, locale: Fix.locale)
        check(board.interval(shown: true) == .seconds(2), "a hidden read leaves nothing for the page to wait on")
        board.apply(Fix.reading(at: 15, busy: 0, total: 2000, received: 0, sent: 0, detail: true),
                    processorCount: 4, locale: Fix.locale)
        check(board.interval(shown: true) == .milliseconds(500) && board.interval(shown: false) == .seconds(15),
              "the first detail read is a baseline, so the next comes soon")
        board.apply(Fix.reading(at: 15.5, busy: 0, total: 3000, received: 500, sent: 50, detail: true, step: 1.5),
                    processorCount: 4, locale: Fix.locale)
        check(board.sample.down == 1000 && board.sample.processes?.count == 2, "rates over the half second")
        check(board.interval(shown: true) == .seconds(2), "then the shown pace")
    }

    static func rates() {
        var board = MonitorBoard()
        board.apply(Fix.reading(at: 10, busy: 100, total: 1000, received: 1_000, sent: 500, detail: true),
                    processorCount: 8, locale: Fix.locale)
        check(board.sample.cpu == nil && board.sample.down == nil, "one read is only a baseline")
        check(board.sample.memory != nil && board.sample.disk != nil, "memory and disk need no baseline")
        board.apply(Fix.reading(at: 12, busy: 400, total: 2000, received: 5_000, sent: 1_500, detail: true),
                    processorCount: 8, locale: Fix.locale)
        check(board.sample.cpu == 0.3, "CPU between the two reads: \(board.sample.cpu ?? -1)")
        check(board.sample.down == 2_000 && board.sample.up == 500, "bytes per second over 2 s")
        var changed = Fix.reading(at: 14, busy: 500, total: 3000, received: 9_000, sent: 2_000, detail: true)
        changed.network?.interfaces = ["en0", "en1"]
        board.apply(changed, processorCount: 8, locale: Fix.locale)
        check(board.sample.down == nil, "a new interface starts a new baseline, never a spike")
        board.apply(Fix.reading(at: 16, busy: 600, total: 4000, received: 1, sent: 1, detail: true),
                    processorCount: 8, locale: Fix.locale)
        check(board.sample.down == nil, "after a reset the next read is the baseline again")
        board.apply(Fix.reading(at: 18, busy: 700, total: 5000, received: 0, sent: 0, detail: true),
                    processorCount: 8, locale: Fix.locale)
        check(board.sample.down == 0 && board.sample.up == 0, "a counter that went back reads as no traffic")
    }

    static func processes() {
        let before: [Int32: UInt64] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0]
        let now = [
            Fix.process(1, "Xcode", seconds: 4, footprint: 2 * Fix.gib),
            Fix.process(2, "Safari", seconds: 1, footprint: Fix.gib),
            Fix.process(3, "mds", seconds: 1, footprint: 3 * Fix.gib),
            Fix.process(4, "Music", seconds: 0, footprint: 1),
            Fix.process(5, "Notes", seconds: 0, footprint: 2),
            Fix.process(6, "Finder", seconds: 0.5, footprint: 1),
            Fix.process(7, "Mail", seconds: 0, footprint: 3),
            Fix.process(9, "new", seconds: 8, footprint: 1),
        ]
        let top = MonitorBoard.top(now, since: before, elapsed: 2, processorCount: 4)
        check(top.map(\.name) == ["Xcode", "mds", "Safari", "Finder", "Mail"],
              "busiest first, ties by footprint, five at most, a new process waits: \(top.map(\.name))")
        check(MonitorBoard.ranked(now, since: before).map(\.pid) == top.map(\.pid),
              "the read names exactly the rows the board lists")
        let unnamed = MonitorProcessTime(pid: 1, cpuNanoseconds: 1, footprint: 0)
        check(MonitorBoard.top([unnamed], since: [1: 0], elapsed: 1, processorCount: 1).first?.name == "pid 1",
              "a row whose name could not be read shows its pid")
        check(top[0].cpu == 0.5, "4 s of CPU over 2 s on 4 cores is half the Mac")
        check(MonitorBoard.top(now, since: before, elapsed: 0, processorCount: 4).isEmpty, "no time, no shares")
    }

    /// Hidden, the page's own reads stop; shown again they start from a fresh baseline, and a sleep is no sample.
    static func gaps() {
        var board = MonitorBoard()
        board.apply(Fix.reading(at: 0, busy: 0, total: 100, received: 0, sent: 0, detail: true),
                    processorCount: 8, locale: Fix.locale)
        board.apply(Fix.reading(at: 2, busy: 50, total: 200, received: 10, sent: 10, detail: true),
                    processorCount: 8, locale: Fix.locale)
        check(board.sample.processes?.isEmpty == false, "two detail reads list processes")
        board.apply(Fix.reading(at: 17, busy: 60, total: 300, received: 0, sent: 0, detail: false),
                    processorCount: 8, locale: Fix.locale)
        check(board.sample.processes == nil && board.sample.down == nil, "hidden reads drop network and processes")
        check(board.sample.cpu == 0.1, "the hot check keeps reading CPU every 15 s")
        board.apply(Fix.reading(at: 19, busy: 70, total: 400, received: 0, sent: 0, detail: true),
                    processorCount: 8, locale: Fix.locale)
        check(board.sample.processes == nil, "shown again, the first detail read is a baseline")
        board.apply(Fix.reading(at: 40, busy: 90, total: 500, received: 0, sent: 0, detail: true),
                    processorCount: 8, locale: Fix.locale)
        check(board.sample.cpu == nil && board.sample.processes == nil, "a gap over 20 s starts again")
    }

    static func page() {
        let board = Fix.board()
        let page = MonitorPage.page(board, locale: Fix.locale)
        check(page.id == "system" && page.order == 20 && page.title == "System", "the System tab after the player")
        guard case .cards(let tiles) = page.blocks.first else { return check(false, "tiles lead the page") }
        check(tiles.cards.map(\.title) == ["CPU", "Memory", "Disk", "Network"], "four tiles")
        check(tiles.cards.allSatisfy { !$0.dimmed }, "every tile has a reading")
        check(meter(tiles.cards[0])?.value == "43%" && meter(tiles.cards[0])?.warning == false, "CPU load")
        check(meter(tiles.cards[1])?.value == "8 GB" && meter(tiles.cards[1])?.trailing == "of 16 GB",
              "memory in binary units: \(meter(tiles.cards[1])?.value ?? "")")
        check(meter(tiles.cards[2])?.value == "400 GB" && tiles.cards[2].caption == "100 GB free",
              "disk in decimal units with its free space: \(meter(tiles.cards[2])?.value ?? "")")
        guard case .notice(_, let down, let up) = tiles.cards[3].body else { return check(false, "network speeds") }
        check(down == "↓ 2 MB/s" && up == "↑ 500 kB/s", "\(down) \(up ?? "")")
        let rows = page.blocks.dropFirst().compactMap { if case .row(let row) = $0 { row } else { nil } }
        check(rows.map(\.title) == ["Top processes", "Xcode", "Safari"], "\(rows.map(\.title))")
        check(rows.allSatisfy { $0.symbol == nil }, "the header lines up with its rows")
        check(MonitorPage.rate(0, Fix.locale) == "0 bytes/s" && MonitorPage.bytes(0, Fix.locale, memory: true) == "0 bytes",
              "an idle network reads a digit, never a word: \(MonitorPage.rate(0, Fix.locale))")
        check(rows[1].trailing == "25%" && rows[1].detail == "2 GB", "CPU share with the memory under it")
        check(MonitorPage.status(board.heat) == nil, "nothing hot, nothing on the closed island")
        let empty = MonitorPage.page(MonitorBoard(), locale: Fix.locale)
        guard case .cards(let none) = empty.blocks.first else { return check(false, "tiles before any read") }
        check(none.cards.prefix(3).allSatisfy(\.dimmed) && meter(none.cards[0])?.value == "–",
              "before a read the tiles are dimmed dashes")
        check(empty.line.text == "Measuring…", "and Home says so")
    }

    static func volumes() {
        let cases: [(String, Bool?, Bool, Bool, Bool?, Bool?, Bool)] = [
            ("external removable", false, true, false, true, false, true),
            ("external ejectable", false, false, true, true, false, true),
            ("external fixed", false, false, false, true, false, true),
            ("card in internal reader", true, true, true, true, false, true),
            ("internal fixed", true, false, false, true, false, false),
            ("network", false, true, true, false, false, false),
            ("locality unknown", false, true, true, nil, false, false),
            ("external startup", false, true, true, true, true, false),
            ("disk image without a bus flag", nil, true, true, true, false, true),
        ]
        for (name, internalBus, removable, ejectable, local, root, expected) in cases {
            let volume = MonitorVolume(path: "/Volumes/\(name)", name: name, size: nil, isInternal: internalBus,
                                       isRemovable: removable, isEjectable: ejectable, isLocal: local,
                                       isRootFileSystem: root)
            check(volume.canEject == expected, name)
        }
        let root = Fix.volume("Startup", path: "/")
        check(!root.canEject, "root falls back to its mount path")
        var network = Fix.volume("Share")
        network.isLocal = false
        let filtered = MonitorPage.page(Fix.board(volumes: [root, network]), locale: Fix.locale)
        check(filtered == MonitorPage.page(Fix.board(), locale: Fix.locale), "no eligible disk leaves the page alone")

        let volumes = [Fix.volume("Disk 10"), Fix.volume("Disk 4"), Fix.volume("Disk 2", path: "/Volumes/B"),
                       Fix.volume("Disk 2", path: "/Volumes/A"), Fix.volume("Disk 3"), Fix.volume("Disk 30")]
        let board = Fix.board(volumes: volumes)
        check(board.sample.volumes.map(\.path) == ["/Volumes/A", "/Volumes/B", "/Volumes/Disk 3", "/Volumes/Disk 4",
                                                   "/Volumes/Disk 10", "/Volumes/Disk 30"],
              "natural name order, ties by path")
        let rows = MonitorPage.page(board, locale: Fix.locale).blocks.compactMap {
            if case .row(let row) = $0 { row } else { nil }
        }
        check(rows.map(\.title) == ["Disks", "Disk 2", "Disk 2", "Disk 3", "Disk 4", "2 more",
                                    "Top processes", "Xcode", "Safari"], "cap at four before the process list")
        check(rows[1].detail == "500 GB" && rows[1].trailing == "Eject" && rows[1].symbol == "externaldrive"
              && rows[1].spoken == "Eject Disk 2, 500 GB", "size and a named VoiceOver action")
        check(rows[0].id == nil && rows[5].id == nil && rows[5].symbol == nil, "header and overflow are plain rows")
    }

    static func ejecting() {
        let volume = Fix.volume("Seagate", path: "/Volumes/Żółć : data")
        let neighbour = Fix.volume("Backup")
        let action = MonitorVolumes.action(for: volume.path)
        check(MonitorVolumes.path(for: action) == volume.path, "spaces, colons and non-ASCII survive the round trip")
        for other in [IslandPage.refreshAction, "eject:", "eject:relative", "media.volume:0.5"] {
            check(MonitorVolumes.path(for: other) == nil, "foreign or malformed action: \(other)")
        }
        var board = Fix.board(volumes: [volume, neighbour])
        let idle = MonitorPage.page(board, locale: Fix.locale)
        guard case .row(let idleRow) = idle.blocks[3] else { return check(false, "the volume row") }
        check(idleRow.id == action, "the idle row can eject")
        board.ejecting.insert(volume.path)
        let active = MonitorPage.page(board, locale: Fix.locale)
        guard case .row(let working) = active.blocks[3] else { return check(false, "the ejecting row") }
        check(working.id == nil && working.trailing == "Ejecting…" && working.spoken == "Ejecting Seagate",
              "the ejecting volume is a plain status row")
        check(active.blocks[2] == idle.blocks[2], "a neighbouring disk stays a button")

        let cases: [(MonitorEjectResult, MonitorEjectOutcome, String)] = [
            (MonitorEjectResult(stillMounted: true), .ejected, "Ejected Seagate"),
            (MonitorEjectResult(errorDomain: NSCocoaErrorDomain, errorCode: 769, stillMounted: false),
             .ejected, "Ejected Seagate"),
            (MonitorEjectResult(errorDomain: NSCocoaErrorDomain, errorCode: 769, holder: "Preview", stillMounted: true),
             .busy("Preview"), "Seagate Is in Use by Preview"),
            (MonitorEjectResult(errorDomain: NSCocoaErrorDomain, errorCode: 769, stillMounted: true),
             .busy(nil), "Seagate Is in Use"),
            (MonitorEjectResult(errorDomain: NSCocoaErrorDomain, errorCode: 768, stillMounted: true),
             .failed, "Couldn’t Eject Seagate"),
            (MonitorEjectResult(errorDomain: NSPOSIXErrorDomain, errorCode: 769, stillMounted: true),
             .failed, "Couldn’t Eject Seagate"),
        ]
        for (result, outcome, text) in cases {
            check(result.outcome == outcome, "eject outcome for \(text)")
            let notice = MonitorPage.ejectNotice(result.outcome, volume: volume)
            let failure = outcome != .ejected
            check(notice.text == text && notice.isFailure == failure && notice.dwell == (failure ? 4 : 2.4),
                  "notice words, tone and dwell for \(text)")
            check(notice.symbol == (failure ? "externaldrive.badge.exclamationmark" : "checkmark"), "notice glyph")
        }
    }

    /// Hot is a yellow meter with a word under it on the page, and a glyph with a word on the closed island.
    static func hotPage() {
        let board = Fix.board(cpu: 0.96, pressure: .critical, freePercent: 3, hotFor: 12)
        check(board.heat.hot == [.cpu, .memory, .disk], "\(board.heat.hot)")
        guard case .cards(let tiles) = MonitorPage.page(board, locale: Fix.locale).blocks.first else {
            return check(false, "tiles")
        }
        let notes = tiles.cards.prefix(3).map { meter($0)?.note }
        check(notes == ["Running hot", "Pressure critical", "Almost full"], "each hot tile says it in words: \(notes)")
        check(tiles.cards.prefix(3).allSatisfy { meter($0)?.warning == true }, "and takes the warning ink")
        let status = MonitorPage.status(board.heat)
        check(status?.id == "system" && status?.symbol == "cpu" && status?.text == "Hot",
              "the closed island names the first hot resource: \(String(describing: status))")
        check(status?.label == "CPU running hot, Memory pressure critical, Startup disk almost full",
              "VoiceOver hears every hot resource")
        var memory = MonitorHeat()
        memory.update(cpu: 0.1, readAt: 0, pressure: .critical, disk: nil)
        check(MonitorPage.status(memory)?.symbol == "memorychip" && MonitorPage.status(memory)?.text == "High",
              "memory's own glyph and word")
        var disk = MonitorHeat()
        disk.update(cpu: 0.1, readAt: 0, pressure: .normal, disk: Fix.disk(freePercent: 3))
        check(MonitorPage.status(disk)?.symbol == "internaldrive" && MonitorPage.status(disk)?.text == "Full",
              "disk's own glyph and word")
        check(MonitorPage.status(disk)?.text.map { $0.count <= 4 } == true, "the pill shows four characters")
    }

    static func homeLine() {
        let quiet = MonitorPage.line(Fix.board(cpu: 0.43, freePercent: 5), locale: Fix.locale)
        check(quiet.text == "Memory 50%" && quiet.symbol == "memorychip" && quiet.detail == "Xcode 25%",
              "the busier of CPU and memory, with the busiest process; a full disk that is not hot stays off: "
                  + "\(quiet.text) \(quiet.detail ?? "")")
        let busy = MonitorPage.line(Fix.board(cpu: 0.88, freePercent: 60), locale: Fix.locale)
        check(busy.text == "CPU 88%" && busy.symbol == "cpu", "\(busy.text)")
        let hot = MonitorPage.line(Fix.board(cpu: 0.2, freePercent: 3), locale: Fix.locale)
        check(hot.text == "Startup disk almost full" && hot.detail == "15 GB free",
              "a hot resource leads the line: \(hot.text) \(hot.detail ?? "")")
    }

    /// Hot is a yellow glyph beside its word on the closed island and on Home; anything else inks as always.
    static func tones() {
        let normal = Fix.board()
        check(MonitorPage.status(normal.heat) == nil && MonitorPage.line(normal, locale: Fix.locale).tone == nil,
              "nothing hot, no tone")
        let busiest = MonitorPage.line(Fix.board(cpu: 0.88, freePercent: 5), locale: Fix.locale)
        check(busiest.text == "CPU 88%" && busiest.tone == nil, "the busiest resource that is not hot takes no tone")
        check(MonitorPage.line(MonitorBoard(), locale: Fix.locale).tone == nil, "measuring takes no tone")
        let cases: [(String, MonitorBoard, MonitorReading)] = [
            ("CPU after the hold", Fix.board(cpu: 0.96, hotFor: 12),
             Fix.reading(at: 16, busy: 1920 + 740, total: 4000, received: 12_000_000, sent: 3_000_000, detail: true,
                         step: 3)),
            ("memory", Fix.board(pressure: .critical),
             Fix.reading(at: 4, busy: 430 * 2 + 430, total: 4000, received: 8_000_000, sent: 2_000_000, detail: true,
                         step: 2)),
            ("disk", Fix.board(freePercent: 3),
             Fix.reading(at: 4, busy: 430 * 2 + 430, total: 4000, received: 8_000_000, sent: 2_000_000, detail: true,
                         freePercent: 5, step: 2)),
        ]
        for (name, hot, cooler) in cases {
            check(hot.heat.hot.count == 1, "\(name) alone runs hot: \(hot.heat.hot)")
            check(MonitorPage.status(hot.heat)?.tone == .warning, "\(name): the closed glyph turns yellow")
            check(MonitorPage.line(hot, locale: Fix.locale).tone == .warning, "\(name): the Home glyph turns yellow")
            var cooled = hot
            cooled.apply(cooler, processorCount: 4, locale: Fix.locale)
            check(cooled.heat.hot.isEmpty, "\(name) leaves hot at its lower mark: \(cooled.heat.hot)")
            check(MonitorPage.status(cooled.heat) == nil && MonitorPage.line(cooled, locale: Fix.locale).tone == nil,
                  "\(name): cooled, no tone")
        }
    }

    static func meter(_ card: IslandCard) -> IslandCardMeter? {
        if case .meters(let meters) = card.body { meters.first } else { nil }
    }
}
