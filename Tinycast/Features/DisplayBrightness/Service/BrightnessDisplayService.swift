import CoreGraphics
import ColorSync
import Foundation

// The lock confines the channels, gamma tables and readings to one hardware transaction at a time.
final class BrightnessDisplayService: @unchecked Sendable {
    enum Operation: Sendable {
        case refresh(names: [UInt32: String])
        case set(Double, BrightnessDisplay.ID)
        case step(up: Bool, fine: Bool, BrightnessDisplay.ID)
    }

    private struct GammaTable {
        let red: [Float]
        let green: [Float]
        let blue: [Float]

        static func read(_ display: UInt32) -> Self? {
            let capacity = CGDisplayGammaTableCapacity(display)
            guard capacity > 0 else { return nil }
            var red = [Float](repeating: 0, count: Int(capacity))
            var green = red
            var blue = red
            var count: UInt32 = 0
            guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success,
                  count > 0 else { return nil }
            return Self(red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))),
                        blue: Array(blue.prefix(Int(count))))
        }

        func apply(_ factor: Double, to display: UInt32) -> Bool {
            CGSetDisplayTransferByTable(display, UInt32(red.count),
                                       red.map { $0 * Float(factor) }, green.map { $0 * Float(factor) },
                                       blue.map { $0 * Float(factor) }) == .success
        }
    }

    private let lock = NSLock()
    private var entries: [BrightnessDisplay] = []
    private var channels: [BrightnessDisplay.ID: BrightnessI2CChannel] = [:]
    private var baselines: [BrightnessDisplay.ID: GammaTable] = [:]

    deinit {
        if !baselines.isEmpty { CGDisplayRestoreColorSyncSettings() }
    }

    @concurrent func perform(_ operation: Operation) async -> [BrightnessDisplay]? {
        lock.withLock {
            guard !Task.isCancelled else { return nil }
            switch operation {
            case .refresh(let names):
                return refresh(names: names)
            case .set(let value, let id):
                guard value.isFinite else { return nil }
                return change(id) { BrightnessLevel(value, softwareOnly: $0.softwareOnly) }
            case .step(let up, let fine, let id):
                return change(id) { $0.stepped(up: up, fine: fine) }
            }
        }
    }

    @concurrent func stop() async {
        lock.withLock {
            if !baselines.isEmpty { CGDisplayRestoreColorSyncSettings() }
            baselines = [:]
            entries = []
            channels = [:]
        }
    }

    private func refresh(names: [UInt32: String]) -> [BrightnessDisplay]? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        var ids = [UInt32](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        let remembered = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.level) })
        let discovered = BrightnessI2CChannel.discover()
        var refreshedChannels: [BrightnessDisplay.ID: BrightnessI2CChannel] = [:]
        var refreshedEntries: [BrightnessDisplay] = []
        for rawValue in ids.prefix(Int(count)) {
            guard !Task.isCancelled else { return nil }
            guard CGDisplayIsActive(rawValue) != 0, CGDisplayIsAsleep(rawValue) == 0,
                  let id = Self.identity(rawValue) else { continue }
            let builtIn = CGDisplayIsBuiltin(rawValue) != 0
            let systemLevel = DisplayServicesBrightness.read(rawValue)
            let channel = builtIn || systemLevel != nil ? nil : discovered[id.uuid]
            let hardwareLevel = systemLevel ?? channel?.read()
            let control: BrightnessDisplay.Control = systemLevel != nil ? .system : hardwareLevel != nil ? .ddc : .software
            let old = remembered[id]
            let value = hardwareLevel.map { reading in
                reading == 0 && old?.softwareOnly == false ? min(old?.value ?? 0, 0) : reading
            } ?? (old?.softwareOnly == true ? old?.value ?? 1 : 1)
            let level = BrightnessLevel(value, softwareOnly: control == .software)
            if control == .ddc { refreshedChannels[id] = channel }
            refreshedEntries.append(BrightnessDisplay(id: id, name: names[rawValue] ?? id.uuid,
                                                      isBuiltIn: builtIn, control: control, level: level))
        }
        guard !Task.isCancelled else { return nil }
        if !baselines.isEmpty { CGDisplayRestoreColorSyncSettings() }
        baselines = [:]
        channels = refreshedChannels
        entries = refreshedEntries
        for index in entries.indices where entries[index].level.isDimmed {
            if !dim(entries[index].level.picture, on: entries[index].id) {
                let softwareOnly = entries[index].control == .software
                entries[index].level = BrightnessLevel(softwareOnly ? 1 : 0, softwareOnly: softwareOnly)
            }
        }
        return entries
    }

    private func change(_ id: BrightnessDisplay.ID,
                        transform: (BrightnessLevel) -> BrightnessLevel) -> [BrightnessDisplay]? {
        guard !Task.isCancelled, Self.isAvailable(id),
              let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        var previous = entries[index].level
        if entries[index].control == .system {
            guard let reading = DisplayServicesBrightness.read(id.rawValue) else { return nil }
            previous = previous.refreshed(hardware: reading)
            if !previous.isDimmed {
                guard dim(1, on: id) else { return nil }
            }
            entries[index].level = previous
        }
        let level = transform(previous)
        let wrote: Bool
        switch entries[index].control {
        case .system:
            wrote = DisplayServicesBrightness.write(level.hardware, to: id.rawValue)
        case .ddc:
            wrote = level.hardware == previous.hardware || channels[id]?.write(level.hardware) == true
        case .software:
            wrote = true
        }
        guard wrote else { return nil }
        guard dim(level.picture, on: id) else {
            switch entries[index].control {
            case .system: _ = DisplayServicesBrightness.write(previous.hardware, to: id.rawValue)
            case .ddc: _ = channels[id]?.write(previous.hardware)
            case .software: break
            }
            return nil
        }
        entries[index].level = level
        return entries
    }

    private func dim(_ factor: Double, on id: BrightnessDisplay.ID) -> Bool {
        if factor >= 1 {
            guard baselines[id] != nil else { return true }
            baselines[id] = nil
            // ColorSync restoration affects every display, so reapply the other owned dimming curves.
            CGDisplayRestoreColorSyncSettings()
            for entry in entries where entry.id != id && entry.level.isDimmed {
                if let baseline = baselines[entry.id], Self.identity(entry.id.rawValue) == entry.id {
                    _ = baseline.apply(entry.level.picture, to: entry.id.rawValue)
                }
            }
            return true
        }
        guard let baseline = baselines[id] ?? GammaTable.read(id.rawValue) else { return false }
        guard baseline.apply(factor, to: id.rawValue) else { return false }
        baselines[id] = baseline
        return true
    }

    static func isAvailable(_ id: BrightnessDisplay.ID) -> Bool {
        identity(id.rawValue) == id && CGDisplayIsActive(id.rawValue) != 0 && CGDisplayIsAsleep(id.rawValue) == 0
    }

    private static func identity(_ id: UInt32) -> BrightnessDisplay.ID? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) else { return nil }
        return .init(rawValue: id, uuid: text as String)
    }
}
