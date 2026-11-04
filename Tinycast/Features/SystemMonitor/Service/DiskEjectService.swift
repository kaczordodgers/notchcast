import AppKit

nonisolated enum DiskEjectService {
    @concurrent static func eject(_ url: URL) async -> DiskEjectResult {
        guard !Task.isCancelled else { return .gone }
        guard isMounted(url) else { return .gone }
        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsInternalKey,
            .volumeIsRootFileSystemKey, .volumeIsEjectableKey]
        do {
            let values = try url.resourceValues(forKeys: keys)
            guard DiskVolume.canEject(isLocal: values.volumeIsLocal,
                                     isInternal: values.volumeIsInternal,
                                     isRoot: values.volumeIsRootFileSystem,
                                     isEjectable: values.volumeIsEjectable)
            else { return .notEjectable }
            guard !Task.isCancelled else { return .gone }
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            return .ejected
        } catch {
            return isMounted(url) ? .busy(error) : .gone
        }
    }

    private static func isMounted(_ url: URL) -> Bool {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil)?
            .contains { $0.standardizedFileURL == url.standardizedFileURL } == true
    }
}
