import Foundation

extension MonitorStore {
    func ejectState(at url: URL) -> DiskEjectState {
        let path = url.standardizedFileURL.path
        guard latest.volumes.contains(where: { $0.mountPath == path }) else { return .idle }
        return ejectStates[path] ?? .idle
    }

    @discardableResult
    func ejectVolume(at url: URL,
                     using eject: @Sendable (URL) async -> DiskEjectResult = DiskEjectService.eject
    ) async -> DiskEjectResult? {
        guard ejectLifecycle.enabled, !Task.isCancelled else { return nil }
        let path = url.standardizedFileURL.path
        if case .ejecting = ejectStates[path] { return nil }
        guard let volume = latest.volumes.first(where: { $0.mountPath == path }) else { return .gone }
        guard volume.isEjectable else { return .notEjectable }
        let generation = ejectLifecycle.generation
        ejectStates[path] = .ejecting
        let result = await eject(URL(filePath: path))
        guard !Task.isCancelled, ejectLifecycle.enabled,
              ejectLifecycle.generation == generation else {
            ejectStates[path] = nil
            return nil
        }
        switch result {
        case .busy(let error):
            ejectStates[path] = .failed(error)
        case .ejected, .gone, .notEjectable: ejectStates[path] = nil
        }
        return result
    }
}
