import CoreAudio
import CoreMediaIO
import Foundation

@MainActor
final class SystemInUseSource: InUseSource {
    private typealias Audio = MicrophoneAudioObject

    private var topology: Audio.Listener?
    private var processes: [Audio.Listener] = []
    private var cameras: [CameraListener] = []
    private var cameraTopology: CameraListener?
    private var change: (@MainActor () -> Void)?
    private var processFailure: MicrophoneInput.Failure?
    private var cameraFailure: MicrophoneInput.Failure?
    var monitoringFailure: MicrophoneInput.Failure? {
        if let status = topology?.status, status != noErr { return .read(status) }
        if let status = cameraTopology?.status, status != noErr { return .read(status) }
        return processFailure ?? cameraFailure
    }

    func start(change: @escaping @MainActor () -> Void) {
        stop()
        self.change = change
        topology = Audio.Listener(Audio.system, Audio.address(kAudioHardwarePropertyProcessObjectList)) { [weak self] in
            self?.listenToProcesses()
            self?.change?()
        }
        cameraTopology = CameraListener(
            CMIOObjectID(kCMIOObjectSystemObject), Self.cameraAddress(kCMIOHardwarePropertyDevices)) { [weak self] in
            self?.listenToCameras()
            self?.change?()
        }
        listenToProcesses()
        listenToCameras()
    }

    func stop() {
        change = nil
        topology = nil
        processes = []
        cameraTopology = nil
        cameras = []
        processFailure = nil
        cameraFailure = nil
    }

    func read() throws(MicrophoneInput.Failure) -> InUseReading {
        var reading = InUseReading()
        for process in try Audio.list(Audio.system, Audio.address(kAudioHardwarePropertyProcessObjectList)) {
            do {
                let running = try Audio.read(process, Audio.address(kAudioProcessPropertyIsRunningInput), initial: UInt32(0))
                guard running != 0 else { continue }
                reading.microphone = true
                if let bundleID = try Audio.text(process, kAudioProcessPropertyBundleID), !bundleID.isEmpty {
                    reading.micApps.append(bundleID)
                }
            } catch .read(kAudioHardwareBadObjectError) {
                continue
            } catch {
                throw error
            }
        }
        for device in try cameraDevices() {
            var property = Self.cameraAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
            var value: UInt32 = 0
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
            guard status == noErr else { throw .read(status) }
            if value != 0 { reading.camera = true }
        }
        return reading
    }

    private func listenToProcesses() {
        guard change != nil else { return }
        processes = []
        processFailure = nil
        do {
            for process in try Audio.list(Audio.system, Audio.address(kAudioHardwarePropertyProcessObjectList)) {
                let listener = Audio.Listener(process, Audio.address(kAudioProcessPropertyIsRunningInput)) { [weak self] in
                    self?.change?()
                }
                if listener.status != noErr { processFailure = .read(listener.status) }
                processes.append(listener)
            }
        } catch {
            processFailure = error
        }
    }

    private func listenToCameras() {
        guard change != nil else { return }
        cameras = []
        cameraFailure = nil
        do {
            for device in try cameraDevices() {
                let listener = CameraListener(
                    device, Self.cameraAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)) { [weak self] in
                    self?.change?()
                }
                if listener.status != noErr { cameraFailure = .read(listener.status) }
                cameras.append(listener)
            }
        } catch {
            cameraFailure = error
        }
    }

    private static func cameraAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
        .init(mSelector: CMIOObjectPropertySelector(selector), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private func cameraDevices() throws(MicrophoneInput.Failure) -> [CMIOObjectID] {
        var property = Self.cameraAddress(kCMIOHardwarePropertyDevices)
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        let status = CMIOObjectGetPropertyDataSize(system, &property, 0, nil, &size)
        guard status == noErr else { throw .read(status) }
        guard size > 0 else { return [] }
        guard size <= 1_048_576, Int(size) % MemoryLayout<CMIOObjectID>.stride == 0 else {
            throw .read(kAudioHardwareBadPropertySizeError)
        }
        var values = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.stride)
        var used: UInt32 = 0
        let result = values.withUnsafeMutableBytes {
            CMIOObjectGetPropertyData(system, &property, 0, nil, size, &used, $0.baseAddress!)
        }
        guard result == noErr else { throw .read(result) }
        return Array(values.prefix(Int(used) / MemoryLayout<CMIOObjectID>.stride))
    }

    @MainActor
    private final class CameraListener {
        let status: OSStatus
        private let device: CMIOObjectID
        private var property: CMIOObjectPropertyAddress
        private let block: CMIOObjectPropertyListenerBlock

        init(_ device: CMIOObjectID, _ property: CMIOObjectPropertyAddress, change: @escaping @MainActor () -> Void) {
            self.device = device
            self.property = property
            let callback: CMIOObjectPropertyListenerBlock = { @Sendable _, _ in Task { @MainActor in change() } }
            block = callback
            var registration = property
            status = CMIOObjectAddPropertyListenerBlock(device, &registration, .main, callback)
        }

        isolated deinit {
            if status == noErr {
                CMIOObjectRemovePropertyListenerBlock(device, &property, .main, block)
            }
        }
    }
}
