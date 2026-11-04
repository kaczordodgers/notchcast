import Foundation
import Observation

@MainActor
@Observable
final class AudioPriorityPreferences: AudioPriorityStore {
    static let shared = AudioPriorityPreferences(suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")
    private let defaults: UserDefaults
    var outputs: [String] { didSet { defaults.set(outputs, forKey: "audioOutputs") } }
    var microphones: [String] { didSet { defaults.set(microphones, forKey: "audioMicrophones") } }
    var outputsEnabled: Bool { didSet { defaults.set(outputsEnabled, forKey: "audioOutputsEnabled") } }
    var microphonesEnabled: Bool {
        didSet { defaults.set(microphonesEnabled, forKey: "audioMicrophonesEnabled") }
    }
    var devices: [AudioPriorityDevice] = []
    var failure: String?
    private var names: [String: String] {
        didSet { defaults.set(names, forKey: "audioDeviceNames") }
    }

    init(suiteName: String) {
        defaults = UserDefaults(suiteName: suiteName)!
        outputs = defaults.stringArray(forKey: "audioOutputs") ?? []
        microphones = defaults.stringArray(forKey: "audioMicrophones") ?? []
        outputsEnabled = defaults.bool(forKey: "audioOutputsEnabled")
        microphonesEnabled = defaults.bool(forKey: "audioMicrophonesEnabled")
        names = defaults.dictionary(forKey: "audioDeviceNames") as? [String: String] ?? [:]
    }

    func update(_ devices: [AudioPriorityDevice]) {
        self.devices = devices
        for device in devices { names[device.uid] = device.name }
    }

    func name(_ uid: String) -> String { names[uid] ?? uid }

    func forget(_ uid: String, direction: AudioPriorityDevice.Direction) {
        guard !devices.contains(where: { $0.uid == uid && $0.direction == direction }) else { return }
        var ranking = ranking(for: direction)
        ranking.uids.removeAll { $0 == uid }
        save(ranking, for: direction)
        if !outputs.contains(uid) && !microphones.contains(uid) { names.removeValue(forKey: uid) }
    }

    func ranking(for direction: AudioPriorityDevice.Direction) -> AudioPriorityRanking {
        direction == .output ? .init(enabled: outputsEnabled, uids: outputs)
            : .init(enabled: microphonesEnabled, uids: microphones)
    }

    func save(_ ranking: AudioPriorityRanking, for direction: AudioPriorityDevice.Direction) {
        if direction == .output {
            outputs = ranking.uids
            outputsEnabled = ranking.enabled
        } else {
            microphones = ranking.uids
            microphonesEnabled = ranking.enabled
        }
    }

    func move(_ uid: String, by offset: Int, direction: AudioPriorityDevice.Direction) {
        var ranking = ranking(for: direction)
        guard let index = ranking.uids.firstIndex(of: uid),
              ranking.uids.indices.contains(index + offset) else { return }
        ranking.uids.swapAt(index, index + offset)
        save(ranking, for: direction)
    }
}
