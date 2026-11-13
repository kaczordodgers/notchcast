import Foundation
import Observation

@MainActor @Observable
final class MicrophoneMute {
    private enum Record: Codable {
        case mute([MicrophoneInput.Level]? = nil)
        case volume([MicrophoneInput.Level])
    }

    nonisolated static let mutedKey = "microphone.muted"
    nonisolated static let restoreKey = "microphone.muted.restore"

    var hotKeyStatus: Int32?
    private(set) var isMuted = false
    private(set) var failures: [MicrophoneInput.Failure] = []

    @ObservationIgnored private let audio: any MicrophoneAudioAccess
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String
    @ObservationIgnored private var records: [String: Record] = [:]
    @ObservationIgnored private var muteWanted: Bool
    @ObservationIgnored private var running = false
    @ObservationIgnored private var validPersistence = true

    init(audio: any MicrophoneAudioAccess, defaults: UserDefaults, key: String = MicrophoneMute.mutedKey) {
        self.audio = audio
        self.defaults = defaults
        self.key = key
        muteWanted = defaults.bool(forKey: key)
        if let data = defaults.data(forKey: key + ".restore") {
            do {
                records = try JSONDecoder().decode([String: Record].self, from: data)
                validPersistence = records.allSatisfy { uid, record in
                    guard !uid.isEmpty else { return false }
                    if case .volume(let levels) = record { return MicrophoneInput.valid(levels) }
                    if case .mute(let levels?) = record { return MicrophoneInput.valid(levels) }
                    return true
                }
            } catch {
                validPersistence = false
            }
        }
    }

    isolated deinit { audio.stop() }

    func start() {
        guard !running else { return }
        running = true
        audio.start { [weak self] in self?.refresh() }
        refresh()
    }

    func stop() {
        running = false
        audio.stop()
    }

    func toggle() {
        if !running { start() }
        setMuted(!muteWanted)
    }

    func setMuted(_ muted: Bool) {
        muteWanted = muted
        defaults.set(muted, forKey: key)
        if !running {
            running = true
            audio.start { [weak self] in self?.refresh() }
        }
        refresh(unmuteUntracked: !muted)
    }

    private func refresh(unmuteUntracked: Bool = false) {
        guard running else { return }
        failures = audio.monitoringFailure.map { [$0] } ?? []
        if !validPersistence {
            records = [:]
            defaults.removeObject(forKey: key + ".restore")
            validPersistence = true
            failures.append(.invalidSavedLevels)
        }
        do {
            let inputs = try audio.inputs()
            if inputs.isEmpty && muteWanted { failures.append(.noInputs) }
            for input in inputs {
                do {
                    if muteWanted {
                        try mute(input)
                    } else if records[input.uid] != nil || unmuteUntracked {
                        try restore(input)
                    }
                } catch {
                    failures.append(error)
                }
            }
            let current = try audio.inputs()
            if !muteWanted { clearRestoredRecords(current) }
            isMuted = !current.isEmpty && current.allSatisfy(\.isMuted)
        } catch {
            failures.append(error)
            isMuted = false
        }
    }

    private func mute(_ input: MicrophoneInput) throws(MicrophoneInput.Failure) {
        if records[input.uid] == nil && input.isMuted { return }
        if case .volume = records[input.uid] {
            try muteVolume(input)
            return
        }
        if !input.mute.isEmpty {
            if records[input.uid] == nil {
                records[input.uid] = .mute(input.mute)
                saveRecords()
            }
            do {
                try write(input.mute.map { .init(element: $0.element, value: 1) }, control: .mute, on: input)
                return
            } catch {
                guard !input.volume.isEmpty else { throw error }
            }
        }
        try muteVolume(input)
    }

    private func muteVolume(_ input: MicrophoneInput) throws(MicrophoneInput.Failure) {
        guard MicrophoneInput.valid(input.volume) else { throw .unsupported(input.uid) }
        if case .volume(let saved) = records[input.uid] {
            guard Set(saved.map(\.element)) == Set(input.volume.map(\.element)) else {
                throw .changedControls(input.uid)
            }
        } else {
            records[input.uid] = .volume(input.volume)
            saveRecords()
        }
        try write(input.volume.map { .init(element: $0.element, value: 0) }, control: .volume, on: input)
    }

    private func restore(_ input: MicrophoneInput) throws(MicrophoneInput.Failure) {
        if case .mute(let levels?) = records[input.uid] {
            try restore(levels, control: .mute, on: input)
            return
        }
        if !input.mute.isEmpty {
            try write(input.mute.map { .init(element: $0.element, value: 0) }, control: .mute, on: input)
        } else if case .mute = records[input.uid] {
            throw .unsupported(input.uid)
        }
        if case .volume(let levels) = records[input.uid] {
            try restore(levels, control: .volume, on: input)
        }
    }

    private func restore(_ levels: [MicrophoneInput.Level], control: MicrophoneInput.Control,
                         on input: MicrophoneInput) throws(MicrophoneInput.Failure) {
        let current = control == .mute ? input.mute : input.volume
        guard Set(levels.map(\.element)) == Set(current.map(\.element)) else {
            throw .changedControls(input.uid)
        }
        try write(levels, control: control, on: input)
    }

    private func clearRestoredRecords(_ inputs: [MicrophoneInput]) {
        var changed = false
        for input in inputs {
            guard let record = records[input.uid] else { continue }
            switch record {
            case .mute(let saved?):
                guard input.mute == saved else { continue }
            case .mute(nil):
                guard !input.mute.isEmpty, input.mute.allSatisfy({ $0.value == 0 }) else { continue }
            case .volume(let saved):
                guard input.volume == saved, input.mute.allSatisfy({ $0.value == 0 }) else { continue }
            }
            records[input.uid] = nil
            changed = true
        }
        if changed { saveRecords() }
    }

    private func write(_ levels: [MicrophoneInput.Level], control: MicrophoneInput.Control,
                       on input: MicrophoneInput) throws(MicrophoneInput.Failure) {
        let current = control == .mute ? input.mute : input.volume
        guard levels != current else { return }
        try audio.write(levels, control: control, on: input)
    }

    private func saveRecords() {
        do {
            defaults.set(try JSONEncoder().encode(records), forKey: key + ".restore")
        } catch {
            validPersistence = false
            failures.append(.invalidSavedLevels)
        }
    }
}
